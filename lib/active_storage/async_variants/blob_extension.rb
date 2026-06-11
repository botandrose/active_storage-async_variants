# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module BlobExtension
      # True when the blob's service is a remote/cloud service that the async
      # processing workers (Crucible, etc.) can reach via presigned URLs. The
      # Disk and Test services return false; the gem then defers to vanilla
      # ActiveStorage rather than trying to enqueue jobs or serve fallbacks.
      # MirrorService doesn't delegate :bucket, so resolve through its primary.
      def bucket_backed?
        resolved = service.respond_to?(:primary) ? service.primary : service
        resolved.respond_to?(:bucket)
      end
    end
  end
end
