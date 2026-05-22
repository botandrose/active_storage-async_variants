# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module AttachmentExtension
      private

      def transform_variants_later
        super
        enqueue_async_variant_jobs
      end

      def enqueue_async_variant_jobs
        return unless blob.bucket_backed?

        named_variants.each do |name, named_variant|
          next unless named_variant.transformations.key?(:processing)

          ActiveStorage::AsyncVariants::ProcessJob.perform_later(
            record, self.name, name.to_s,
          )
        end
      end
    end
  end
end
