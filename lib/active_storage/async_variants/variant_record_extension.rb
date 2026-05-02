# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariantRecordExtension
      extend ActiveSupport::Concern

      included do
        after_update_commit :touch_attached_records, if: :became_processed?
      end

      private

      def became_processed?
        saved_change_to_state? && state == "processed"
      end

      def touch_attached_records
        blob.attachments.includes(:record).each do |attachment|
          attachment.record&.touch
        end
      end
    end
  end
end
