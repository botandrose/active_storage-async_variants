# frozen_string_literal: true

class AddHeartbeatColumnsToVariantRecords < ActiveRecord::Migration[7.2]
  def change
    add_column :active_storage_variant_records, :progress, :integer, if_not_exists: true
    add_column :active_storage_variant_records, :last_heartbeat_at, :datetime, if_not_exists: true
  end
end
