# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariationExtension
      ASYNC_KEYS = %i[processing failed transformer].freeze

      def initialize(transformations)
        if transformations.is_a?(Hash)
          @async_options = transformations.slice(*ASYNC_KEYS)
          super(transformations.except(*ASYNC_KEYS))
        else
          @async_options = {}
          super
        end
        ActiveStorage::AsyncVariants::Registry.register(digest, @async_options) if @async_options[:processing].present?
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
