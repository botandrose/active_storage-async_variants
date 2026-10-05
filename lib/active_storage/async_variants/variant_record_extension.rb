# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariantRecordExtension
      extend ActiveSupport::Concern

      included do
        after_update_commit :touch_attached_records, if: :reached_terminal_state?
      end

      def processed?
        state == "processed"
      end

      # A run that stopped heartbeating is presumed dead, so it may be retried.
      def in_flight?
        state == "processing" && last_heartbeat_at.present? && last_heartbeat_at > ActiveStorage::AsyncVariants.heartbeat_stale_after.ago
      end

      private

      # processed and failed are terminal states: cache fragments built when
      # state was pending/processing need to be invalidated so the next
      # render sees the new state (swaps the processing box for the failed
      # error state, swaps src to the direct CDN URL, etc.).
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
