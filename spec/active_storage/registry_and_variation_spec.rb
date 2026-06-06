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


  describe "named-variant declaration eagerly warms the registry" do
    # Ensures cold Puma workers can resolve URL-reconstructed variations
    # without depending on having rendered a view that touches the named
    # variant first.
    it "registers async_options when has_X_attached declares a variant with :processing" do
      Class.new(ActiveRecord::Base) do
        self.table_name = "users"
        has_one_attached :decl_warmed_photo do |a|
          a.variant :decl_warmed,
            resize_to_limit: [123, 123], format: "png",
            transformer: FakePreviewTransformer,
            processing: "/decl-warmed.svg"
        end
      end

      # Compute the digest the controller would see (a Variation with no
      # async_options, since the URL key strips them). Use except() rather
      # than wrap() so we don't accidentally warm the registry ourselves.
      lookup_digest = ActiveStorage::Variation.wrap(
        resize_to_limit: [123, 123], format: "png",
      ).digest

      expect(ActiveStorage::AsyncVariants::Registry[lookup_digest])
        .to include(processing: "/decl-warmed.svg")
    end

    it "does not register async_options for variants declared without :processing" do
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
