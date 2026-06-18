# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariationExtension
      # Stripped before stock sees them (it would treat either as an unknown
      # image operation). `:transformer` is the async opt-in. `:async` is
      # deprecated and ignored -- stripped only so old declarations don't leak
      # it into stock's pipeline; name a transformer to go async.
      STRIP_KEYS = %i[transformer async].freeze

      def initialize(transformations)
        if transformations.is_a?(Hash)
          @async_options = transformations.slice(:transformer)
          super(transformations.except(*STRIP_KEYS))
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
