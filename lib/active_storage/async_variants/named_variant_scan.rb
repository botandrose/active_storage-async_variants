# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    # Finds the async named-variant declaration whose transformations match a
    # variation, starting from a blob's attachments. Used to recover the
    # :transformer option when the Registry is cold, and by
    # Preview/VariantWithRecord enqueue paths to locate the attachment to
    # dispatch ProcessJob against.
    #
    # Walks one level up through a preview_image attachment so a lookup from a
    # video's extracted frame still finds the named variant declared on the
    # parent record's source-video field.
    #
    # Candidates are compared structurally (order-insensitive, JSON-normalized)
    # against the declared transformations, never by instantiating
    # attachment.variant -- which raises InvariableError for previewable blobs.
    module NamedVariantScan
      module_function

      def find(blob, variation, depth: 0)
        blob.attachments.each do |attachment|
          if attachment.name == "preview_image" && attachment.record_type == "ActiveStorage::Blob" && depth < 1
            source = ActiveStorage::Blob.find_by(id: attachment.record_id)
            result = source && find(source, variation, depth: depth + 1)
            return result if result
            next
          end

          attachment.send(:named_variants).each do |name, named_variant|
            candidate = ActiveStorage::Variation.wrap(named_variant.transformations)
            next unless candidate.async_options[:transformer]
            return [attachment, name, candidate.async_options] if matches?(candidate, variation)
          end
        end
        nil
      end

      # A format-less declaration matches any target format, because runtime
      # resolution (Blob#variant's default_to) adds a blob-dependent format:
      # the declaration never carries.
      def matches?(candidate, variation)
        declared = normalize(candidate.transformations)
        target = normalize(variation.transformations)
        declared_format = declared.delete("format")
        target_format = target.delete("format")
        declared == target && (declared_format.nil? || declared_format == target_format)
      end

      def normalize(transformations)
        JSON.parse(transformations.to_json)
      end
    end
  end
end
