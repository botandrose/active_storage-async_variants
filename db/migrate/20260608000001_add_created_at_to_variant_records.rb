# frozen_string_literal: true

class AddCreatedAtToVariantRecords < ActiveRecord::Migration[7.2]
  def change
    add_column :active_storage_variant_records, :created_at, :datetime, if_not_exists: true
  end
end
