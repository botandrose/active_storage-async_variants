# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module RepresentationsRedirectControllerExtension
      ASYNC_HEADER = "X-Async-Variant-State"
      INTERCEPT_STATES = %w[pending processing failed].freeze

      def show
        state = @representation.async_state
        if INTERCEPT_STATES.include?(state)
          fallback = @representation.url(disposition: params[:disposition])
          if fallback.is_a?(String) && fallback.start_with?("/")
            path = Rails.public_path.join(fallback.delete_prefix("/"))
            if File.exist?(path)
              response.set_header(ASYNC_HEADER, state)
              response.set_header("Cache-Control", "no-store, private")
              return send_file path, disposition: "inline"
            end
          end
        end
        super
      end
    end
  end
end
