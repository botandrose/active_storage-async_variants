# frozen_string_literal: true

require "monitor"

module ActiveStorage
  module AsyncVariants
    # Process-wide lookup of async_options keyed by Variation#digest.
    #
    # Populated lazily by VariationExtension#initialize whenever a Variation is
    # constructed with :transformer in its async_options -- which happens on
    # every view-side `attachment.variant(:name)` call. The redirect controller
    # then resolves async_options by digest without scanning blob.attachments
    # for a transformations-match.
    #
    # Cold-worker behavior: if a worker receives a redirect-URL request before
    # any view-side call has registered the variant's digest, the lookup misses
    # and resolution falls through to standard Rails (no leak, no spinner).
    # Self-warms on subsequent view requests.
    class Registry
      MONITOR = Monitor.new
      STORE = {}

      class << self
        def register(digest, async_options)
          MONITOR.synchronize { STORE[digest] = async_options }
        end

        def [](digest)
          MONITOR.synchronize { STORE[digest] }
        end

        def clear
          MONITOR.synchronize { STORE.clear }
        end
      end
    end
  end
end
