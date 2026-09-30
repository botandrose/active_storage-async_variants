# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module AttachmentExtension
      private

      # Stock would also preprocess an async variant: a TransformJob, or a PreviewImageJob that runs the local previewer.
      def transform_variants_later
        without_async_variants { super }
        enqueue_async_variant_jobs
      end

      def named_variants
        return super unless @without_async_variants
        super.reject { |_name, named_variant| async_variant?(named_variant) }
      end

      def without_async_variants
        @without_async_variants = true
        yield
      ensure
        @without_async_variants = false
      end

      def enqueue_async_variant_jobs
        return unless blob.bucket_backed?

        named_variants.each do |name, named_variant|
          next unless async_variant?(named_variant) && named_variant.preprocessed?(record)

          ActiveStorage::AsyncVariants::ProcessJob.perform_later(
            record, self.name, name.to_s,
          )
        end
      end

      def async_variant?(named_variant)
        named_variant.transformations.key?(:transformer)
      end
    end
  end
end
