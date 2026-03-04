# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    class Transformer
      def process(file, **options)
        raise NotImplementedError, "#{self.class}#process must return { io:, content_type:, filename: }"
      end

      def initiate(source_url:, callback_url:, **options)
        raise NotImplementedError, "#{self.class}#initiate must kick off external processing"
      end

      def process_preview(blob:, variation:)
        raise NotImplementedError, "#{self.class}#process_preview must handle preview generation"
      end

      def inline?
        self.class.instance_method(:process).owner != ActiveStorage::AsyncVariants::Transformer
      end
    end
  end
end
