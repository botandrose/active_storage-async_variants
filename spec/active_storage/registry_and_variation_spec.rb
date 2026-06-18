# frozen_string_literal: true

RSpec.describe "async variants: registry and Variation" do
  include_context "with an attached avatar"

  describe "Variation with non-Hash input" do
    it "defaults async_options to empty hash" do
      transformations = Struct.new(:deep_symbolize_keys).new({})
      variation = ActiveStorage::Variation.new(transformations)
      expect(variation.async_options).to eq({})
    end
  end

  describe "deprecated async: key" do
    # Tolerated for backward compatibility: stripped so it never leaks into
    # stock's image pipeline, but it no longer opts a variant into async --
    # only a transformer does.
    it "is stripped from the transformations and ignored" do
      variation = ActiveStorage::Variation.wrap(resize_to_limit: [10, 10], async: true)

      expect(variation.transformations).to eq(resize_to_limit: [10, 10])
      expect(variation.async_options).to eq({})
    end
  end


  describe "named-variant declaration eagerly warms the registry" do
    # Ensures cold Puma workers can resolve URL-reconstructed variations
    # without depending on having rendered a view that touches the named
    # variant first.
    it "registers async_options when has_X_attached declares a variant with a transformer" do
      Class.new(ActiveRecord::Base) do
        self.table_name = "users"
        has_one_attached :decl_warmed_photo do |a|
          a.variant :decl_warmed,
            resize_to_limit: [123, 123], format: "png",
            transformer: FakePreviewTransformer
        end
      end

      # Compute the digest the controller would see (a Variation with no
      # async_options, since the URL key strips them). Use wrap() with only the
      # plain transformations so we don't accidentally warm the registry ourselves.
      lookup_digest = ActiveStorage::Variation.wrap(
        resize_to_limit: [123, 123], format: "png",
      ).digest

      expect(ActiveStorage::AsyncVariants::Registry[lookup_digest])
        .to include(transformer: FakePreviewTransformer)
    end

    it "does not register async_options for variants declared without a transformer" do
      Class.new(ActiveRecord::Base) do
        self.table_name = "users"
        has_one_attached :decl_sync_photo do |a|
          a.variant :decl_sync, resize_to_limit: [124, 124], format: "png"
        end
      end

      lookup_digest = ActiveStorage::Variation.wrap(
        resize_to_limit: [124, 124], format: "png",
      ).digest

      expect(ActiveStorage::AsyncVariants::Registry[lookup_digest]).to be_nil
    end
  end
end
