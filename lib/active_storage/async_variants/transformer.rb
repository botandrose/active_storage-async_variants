# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    # Naming a transformer on a variant is what opts it into async processing.
    # Three kinds, distinguished by what they override:
    #
    # - standard (overrides neither) -- runs the stock Active Storage variant
    #   pipeline in the background. Use the built-in Standard below.
    # - inline (overrides #process) -- does the work in the worker, returns
    #   { io:, content_type:, filename: }.
    # - external (overrides #initiate) -- hands off to a remote service that
    #   POSTs back to the callback URL when done.
    class Transformer
      def process(file, **options)
        raise NotImplementedError, "#{self.class}#process must return { io:, content_type:, filename: }"
      end

      def initiate(source_url:, callback_url:, **options)
        raise NotImplementedError, "#{self.class}#initiate must kick off external processing"
      end

      def inline?
        overrides?(:process)
      end

      def external?
        overrides?(:initiate)
      end

      def standard?
        !inline? && !external?
      end

      private

      def overrides?(method_name)
        self.class.instance_method(method_name).owner != ActiveStorage::AsyncVariants::Transformer
      end
    end

    # Async processing via the stock Active Storage variant pipeline -- the
    # replacement for the old bare `async: true` (no transformer) declaration.
    #
    #   attachable.variant :thumb, resize_to_limit: [100, 100],
    #     transformer: ActiveStorage::AsyncVariants::Standard
    class Standard < Transformer
    end
  end
end
