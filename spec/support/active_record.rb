# frozen_string_literal: true

def silence_stream(stream)
  old_stream = stream.dup
  stream.reopen(IO::NULL)
  stream.sync = true
  yield
ensure
  stream.reopen(old_stream)
  old_stream.close
end

RSpec.configure do |config|
  config.before(:all) do
    ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"

    silence_stream(STDOUT) do
      ActiveRecord::Base.include GlobalID::Identification

      ActiveRecord::Schema.define do
        create_table :active_storage_blobs do |t|
          t.string :key, null: false
          t.string :filename, null: false
          t.string :content_type
          t.text :metadata
          t.string :service_name, null: false
          t.bigint :byte_size, null: false
          t.string :checksum
          t.datetime :created_at, null: false
          t.index [:key], unique: true
        end

        create_table :active_storage_attachments do |t|
          t.string :name, null: false
          t.references :record, null: false, polymorphic: true, index: false
          t.references :blob, null: false
          t.datetime :created_at, null: false
          t.index [:record_type, :record_id, :name, :blob_id], name: "index_active_storage_attachments_uniqueness", unique: true
          t.foreign_key :active_storage_blobs, column: :blob_id
        end

        create_table :active_storage_variant_records do |t|
          t.belongs_to :blob, null: false, index: false
          t.string :variation_digest, null: false
          t.string :state, default: "pending"
          t.text :error
          t.integer :attempts, default: 0
          t.index [:blob_id, :variation_digest], name: "index_active_storage_variant_records_uniqueness", unique: true
          t.foreign_key :active_storage_blobs, column: :blob_id
        end

        create_table :users do |t|
          t.timestamps
        end
      end
    end

    # A simple inline transformer that copies the file unchanged
    class CopyTransformer < ActiveStorage::AsyncVariants::Transformer
      def process(file, **options)
        { io: file, content_type: "image/png", filename: "copy.png" }
      end
    end

    # A transformer that always fails
    class FailingTransformer < ActiveStorage::AsyncVariants::Transformer
      def process(file, **options)
        raise "ffmpeg exited with status 1"
      end
    end

    # An external transformer that records what it was called with
    class FakeExternalTransformer < ActiveStorage::AsyncVariants::Transformer
      cattr_accessor :last_call

      def initiate(source_url:, callback_url:, **options)
        self.class.last_call = {
          source_url: source_url,
          callback_url: callback_url,
          options: options,
        }
      end
    end

    # A transformer that implements process_preview (inline preview generation)
    class FakePreviewTransformer < ActiveStorage::AsyncVariants::Transformer
      cattr_accessor :process_preview_called

      def process_preview(blob:, variation:)
        self.class.process_preview_called = true

        preview_image_blob = ActiveStorage::Blob.create_and_upload!(
          io: File.open("spec/support/fixtures/image.png"),
          filename: "preview.png",
          content_type: "image/png",
          service_name: blob.service.name,
        )
        blob.preview_image.attach(preview_image_blob)

        variant_record = preview_image_blob.variant_records.create_or_find_by!(variation_digest: variation.digest)
        variant_record.image.attach(
          io: File.open("spec/support/fixtures/image.png"),
          filename: "thumb.png",
          content_type: "image/png",
          service_name: blob.service.name,
        )
        variant_record.update!(state: "processed")
      end
    end

    class User < ActiveRecord::Base
      has_one_attached :avatar do |attachable|
        attachable.variant :thumb, resize_to_limit: [100, 100], fallback: :original
        attachable.variant :thumb_sync, resize_to_limit: [100, 100]
        attachable.variant :thumb_blank, resize_to_limit: [100, 100], fallback: :blank
        attachable.variant :thumb_custom, resize_to_limit: [100, 100], fallback: ->(blob) { "/placeholders/processing.svg" }
        attachable.variant :thumb_inline, transformer: CopyTransformer, fallback: :original
        attachable.variant :thumb_failing, transformer: FailingTransformer, fallback: :original
        attachable.variant :thumb_external, transformer: FakeExternalTransformer, fallback: :original
      end
    end
  end

  config.after do
    User.delete_all
    ActiveStorage::Attachment.delete_all
    ActiveStorage::VariantRecord.delete_all
    ActiveStorage::Blob.delete_all
  end
end

def create_variant_record(variant, state: "pending", error: nil)
  blob = variant.blob
  blob.variant_records.create!(
    variation_digest: variant.variation.digest,
    state: state,
    error: error,
  )
end

def simulate_processed_variant(variant)
  record = create_variant_record(variant, state: "processed")
  record.image.attach(
    io: File.open("spec/support/fixtures/image.png"),
    filename: "thumb.png",
    content_type: "image/png",
    service_name: "test",
  )
  record
end
