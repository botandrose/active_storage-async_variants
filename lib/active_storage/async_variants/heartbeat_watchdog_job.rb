# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    # External transforms free the worker at `initiate` and report progress via
    # heartbeats; if the service dies, no terminal callback arrives and the
    # record would sit in "processing" forever. This flips it to "failed" once
    # the heartbeats go stale, re-arming itself each tick until then.
    class HeartbeatWatchdogJob < ActiveJob::Base
      # A retry destroys the record, so a re-armed job has nothing left to watch.
      discard_on ActiveJob::DeserializationError

      def perform(variant_record)
        stale_after = ActiveStorage::AsyncVariants.heartbeat_stale_after
        active = ActiveStorage::VariantRecord.where(id: variant_record.id, state: %w[pending processing])
        stale = active.where("last_heartbeat_at < ?", Time.current - stale_after)

        # Atomic check-and-set: a success/progress callback landing in the same
        # instant moves the row out of `stale` and wins, instead of being clobbered.
        marked_failed_count = stale.update_all(
          state: "failed",
          error: "Transcoding stalled: no heartbeat for over #{stale_after.to_i}s",
        )

        if marked_failed_count.positive?
          touch_consumers(variant_record)
        elsif active.any?
          self.class.set(wait: stale_after).perform_later(variant_record)
        end
      end

      private

      # update_all skips the terminal-state touch, so invalidate consumer caches by hand.
      def touch_consumers(variant_record)
        variant_record.blob.attachments.includes(:record).each { |a| a.record&.touch }
      end
    end
  end
end
