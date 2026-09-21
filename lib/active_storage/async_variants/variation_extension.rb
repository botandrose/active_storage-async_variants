# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariationExtension
      # Stripped before stock sees it (it would treat it as an unknown image
      # operation). Naming a `:transformer` is the async opt-in.
      def initialize(transformations)
        if transformations.is_a?(Hash)
          if transformations.key?(:async)
            raise ArgumentError, "async: is no longer supported; name a transformer: to opt a variant into async processing"
          end
          @async_options = transformations.slice(:transformer)
          super(transformations.except(:transformer))
        else
          @async_options = {}
          super
        end
        ActiveStorage::AsyncVariants::Registry.register(digest, @async_options) if @async_options[:transformer]
      end

      def async_options
        @async_options || {}
      end

      def default_to(defaults)
        self.class.new(transformations.merge(@async_options).reverse_merge(defaults))
      end
    end
  end
end
