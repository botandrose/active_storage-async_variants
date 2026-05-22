# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module BlobExtension
      # True when the blob's service is a remote/cloud service that the async
      # processing workers (Crucible, etc.) can reach via presigned URLs. The
      # Disk and Test services return false; the gem then defers to vanilla
      # ActiveStorage rather than trying to enqueue jobs or serve fallbacks.
      def bucket_backed?
        service.respond_to?(:bucket)
      end
    end
  end
end
