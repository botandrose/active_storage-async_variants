# frozen_string_literal: true

# Schema + dummy User model + helpers shared by RSpec and Cucumber.

module DummySchema
  # Use a file DB so Capybara's server process (which boots Rails in a
  # different thread/connection pool) sees the same data. RSpec uses an
  # in-memory DB instead — set DUMMY_DB=memory to force that.
  DB_PATH = if ENV["DUMMY_DB"] == "memory"
    ":memory:"
  else
    File.expand_path("../../tmp/dummy_test.sqlite3", __dir__)
  end

  def self.load!
    return if @loaded
    @loaded = true

    if DB_PATH != ":memory:"
      FileUtils.mkdir_p File.dirname(DB_PATH)
      File.unlink(DB_PATH) if File.exist?(DB_PATH)
    end
    ActiveRecord::Base.establish_connection adapter: "sqlite3", database: DB_PATH
    ActiveRecord::Base.include GlobalID::Identification

    silence_stream($stdout) do
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
          t.index [:blob_id, :variation_digest], name: "index_active_storage_variant_records_uniqueness", unique: true
          t.foreign_key :active_storage_blobs, column: :blob_id
        end

        create_table :users do |t|
          t.timestamps
        end
      end

      ActiveRecord::Migration.verbose = false
      ActiveRecord::MigrationContext.new([File.expand_path("../../db/migrate", __dir__)]).migrate
    end

    # Transformers shared by all suites.
    Object.const_set :CopyTransformer, Class.new(ActiveStorage::AsyncVariants::Transformer) {
      def process(file, **options)
        { io: file, content_type: "image/png", filename: "copy.png" }
      end
    }

    Object.const_set :FailingTransformer, Class.new(ActiveStorage::AsyncVariants::Transformer) {
      def process(file, **options)
        raise "ffmpeg exited with status 1"
      end
    }

    Object.const_set :FakeExternalTransformer, Class.new(ActiveStorage::AsyncVariants::Transformer) {
      cattr_accessor :last_call
      def initiate(source_url:, callback_url:, **options)
        self.class.last_call = { source_url:, callback_url:, options: }
      end
    }

    Object.const_set :FakePreviewTransformer, CopyTransformer

    # Stands in for ffmpeg: accepts video blobs and "extracts" a fixture frame.
    Object.const_set :FakePreviewer, Class.new(ActiveStorage::Previewer) {
      def self.accept?(blob)
        blob.video?
      end

      def preview(**options)
        yield io: File.open("spec/support/fixtures/image.png"),
          filename: "frame.jpg", content_type: "image/jpeg", **options
      end
    }
    ActiveStorage.previewers = [FakePreviewer]

    Object.const_set :User, Class.new(ActiveRecord::Base) {
      has_one_attached :avatar do |attachable|
        attachable.variant :thumb,          resize_to_limit: [100, 100], async: true
        attachable.variant :thumb_sync,     resize_to_limit: [200, 200]
        attachable.variant :thumb_inline,   transformer: CopyTransformer,         async: true
        attachable.variant :thumb_failing,  transformer: FailingTransformer,      async: true
        attachable.variant :thumb_external, transformer: FakeExternalTransformer, async: true
        attachable.variant :thumb_proc,     resize_to_limit: [600, 600], async: true
        attachable.variant :thumb_preview,  resize_to_limit: [101, 101], transformer: FakePreviewTransformer, async: true
      end

      has_one_attached :video do |attachable|
        attachable.variant :poster,        resize_to_limit: [300, 300], format: :jpg,  transformer: FakeExternalTransformer, async: true
        attachable.variant :poster_web,    resize_to_limit: [600, 338], format: :webp, transformer: FakeExternalTransformer, async: true
        attachable.variant :poster_inline, resize_to_limit: [50, 50],   format: :png,  transformer: CopyTransformer,         async: true
      end
    }
  end

  def self.cleanup!
    User.delete_all
    ActiveStorage::Attachment.delete_all
    ActiveStorage::VariantRecord.delete_all
    ActiveStorage::Blob.delete_all
    ActiveStorage::AsyncVariants::Registry.clear
  end
end

def silence_stream(stream)
  old_stream = stream.dup
  stream.reopen(IO::NULL)
  stream.sync = true
  yield
ensure
  stream.reopen(old_stream)
  old_stream.close
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

def attach_avatar_to(user)
  user.avatar.attach(
    io: File.open("spec/support/fixtures/image.png"),
    filename: "image.png",
    content_type: "image/png",
    service_name: "test",
  )
end

def attach_video_to(user)
  user.video.attach(
    io: File.open("spec/support/fixtures/image.png"),
    filename: "movie.mp4",
    content_type: "video/mp4",
    identify: false,
    service_name: "test",
  )
end

# Builds the stock preview graph in a processed state: a real frame attached as
# preview_image, the variant record on the frame blob, and the variant image.
def simulate_processed_preview(preview)
  preview.blob.preview_image.attach(
    io: File.open("spec/support/fixtures/image.png"),
    filename: "frame.jpg",
    content_type: "image/jpeg",
    service_name: "test",
  )
  record = create_variant_record(preview.send(:variant), state: "processed")
  record.image.attach(
    io: File.open("spec/support/fixtures/image.png"),
    filename: "poster.jpg",
    content_type: "image/jpeg",
    service_name: "test",
  )
  record
end
