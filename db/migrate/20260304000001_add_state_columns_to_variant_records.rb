# frozen_string_literal: true

class AddStateColumnsToVariantRecords < ActiveRecord::Migration[7.2]
  def change
    add_column :active_storage_variant_records, :state, :string, default: "pending", if_not_exists: true
    add_column :active_storage_variant_records, :error, :text, if_not_exists: true
    add_column :active_storage_variant_records, :attempts, :integer, default: 0, if_not_exists: true
  end
end
