# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    # Eagerly warm the digest-keyed Registry when a named variant is declared
    # via has_X_attached's block:
    #
    #   has_one_attached :avatar do |attachable|
    #     attachable.variant :thumb, resize_to_limit: [150, 150], format: "webp",
    #       transformer: Crucible, processing: "/spinner.svg"
    #   end
    #
    # Without this, the Registry only warms when view-side code calls
    # `attachment.variant(:thumb)` -- so a Puma worker that has never rendered
    # a view for the variant misses on URL-reconstructed lookups.
    #
    # Caveat: registration uses the declared transformations. Rails applies a
    # blob-dependent default `format:` at runtime via default_to. Variants that
    # specify `format:` explicitly register the same digest the URL carries
    # (cold-resolvable). Variants that rely on the format default still warm
    # lazily on first view-side call against a blob of that content type.
    module ReflectionExtension
      def variant(name, transformations)
        super
        return unless transformations.is_a?(Hash)
        # Mirror Blob#variant at runtime: wrap and default_to. The default_to
        # call reorders hash keys (default key first) so the registered digest
        # matches the URL-side digest for variants that declare an explicit
        # `format:`. Variants without an explicit `format:` still warm lazily
        # on first view-side call against a blob of that content type.
        ActiveStorage::Variation.wrap(transformations).default_to(format: :png)
      end
    end
  end
end
