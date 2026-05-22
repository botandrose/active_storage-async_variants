# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariantRecordExtension
      extend ActiveSupport::Concern

      included do
        after_update_commit :touch_attached_records, if: :reached_terminal_state?
      end

      private

      # processed and failed are terminal states: cache fragments built when
      # state was pending/processing need to be invalidated so the next
      # render sees the new state (and serves the failed: fallback URL,
      # swaps src to the direct CDN URL, etc.).
      def reached_terminal_state?
        saved_change_to_state? && %w[processed failed].include?(state)
      end

      def touch_attached_records
        blob.attachments.includes(:record).each do |attachment|
          attachment.record&.touch
        end
      end
    end
  end
end
