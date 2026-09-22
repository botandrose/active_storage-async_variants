# frozen_string_literal: true

# Async previews must persist the same graph stock Active Storage builds:
#
#   video Blob
#    └─ Attachment "preview_image" ──▶ frame Blob (full-size grab)
#         └─ VariantRecord (on the frame blob)
#              └─ Attachment "image" ──▶ variant Blob
#
RSpec.describe "async variants: stock preview structure" do
  before do
    @user = User.create!
    attach_video_to(@user)
  end

  let(:video_blob) { @user.video.blob }

  describe "ProcessJob via the preview path (external transformer)" do
    it "attaches a frame placeholder as preview_image and puts the record on the frame blob" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster)

      expect(video_blob.preview_image).to be_attached
      frame = video_blob.preview_image.blob
      expect(frame.content_type).to eq("image/jpeg")
      expect(frame.byte_size).to eq(0)
      expect(frame.checksum).to eq("0")

      expect(video_blob.variant_records.count).to eq(0)
      record = frame.variant_records.sole
      expect(record.state).to eq("processing")
    end

    it "initiates the transformer against the video source with the frame record's callback" do
      FakeExternalTransformer.last_call = nil

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster)

      record = video_blob.preview_image.blob.variant_records.sole
      expect(FakeExternalTransformer.last_call[:source_url]).to be_present
      expect(FakeExternalTransformer.last_call[:options][:variant_record_id]).to eq(record.id)
      expect(FakeExternalTransformer.last_call[:callback_url]).to include(
        ActiveStorage::AsyncVariants.callback_token_for(record),
      )
    end

    it "passes the resolved transformations including the declared format" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster)

      options = FakeExternalTransformer.last_call[:options]
      expect(options[:resize_to_limit]).to eq([300, 300])
      expect(options[:format].to_s).to eq("jpg")
    end

    it "reuses the existing frame blob for additional preview variants" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster)
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster_web)

      frame = video_blob.preview_image.blob
      expect(ActiveStorage::Blob.where(content_type: "image/jpeg").count).to eq(1)
      expect(frame.variant_records.count).to eq(2)
    end
  end

  describe "success callback", type: :request do
    it "reconciles both placeholder blobs and the preview serves the variant" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster)
      frame = video_blob.preview_image.blob
      record = frame.variant_records.sole
      # The external transformer attaches the output placeholder, like Crucible does.
      record.image.attach(
        ActiveStorage::Blob.create_before_direct_upload!(
          filename: "poster.jpg", content_type: "image/jpeg",
          service_name: "test", byte_size: 0, checksum: "0",
        ),
      )
      token = ActiveStorage::AsyncVariants.callback_token_for(record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "success", byte_size: 4567, checksum: "QnQbhWqM4JDca/q1RCowig==",
                  preview_image_byte_size: 8910, preview_image_checksum: "h8arsBrB0ACLrhqOw723VQ==" },
        as: :json

      expect(response).to have_http_status(:ok)
      expect(frame.reload.byte_size).to eq(8910)
      expect(frame.checksum).to eq("h8arsBrB0ACLrhqOw723VQ==")
      expect(record.image.blob.reload.byte_size).to eq(4567)

      preview = @user.video.preview(:poster)
      expect(preview.processed?).to be true
      expect(preview.url).to end_with("/poster.jpg")
      expect(preview.key).to eq(record.image.blob.key)
    end
  end

  describe "view-side Preview state" do
    it "serves the original video while pending" do
      preview = @user.video.preview(:poster)

      expect(preview.processed?).to be false
      expect(preview.async_state).to eq("pending")
      expect(preview.url).to end_with("/movie.mp4")
    end

    it "reports the frame record's state once processing has begun, still serving the original" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster)

      preview = @user.video.preview(:poster)
      expect(preview.async_state).to eq("processing")
      expect(preview.url).to end_with("/movie.mp4")
    end
  end

  describe "Preview#enqueue! on a previewable blob" do
    it "creates the frame placeholder and a pending record on it, and enqueues ProcessJob" do
      preview = @user.video.preview(:poster)

      expect {
        preview.enqueue!
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)

      frame = video_blob.preview_image.blob
      expect(frame.checksum).to eq("0")
      expect(frame.variant_records.sole.state).to eq("pending")
    end

    it "is idempotent once the frame record exists" do
      @user.video.preview(:poster).enqueue!

      expect {
        @user.video.preview(:poster).enqueue!
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end
  end

  describe ".ensure_preview_image_placeholder!" do
    # A video's :thumb and :web are both image variants, so two ProcessJobs run this
    # concurrently for one blob. The loser must not attach a second frame: whichever
    # frame loses is invisible to has_one :preview_image, stranding its records.
    it "returns the frame a concurrent caller attached while it waited to serialize" do
      blob = video_blob
      winner = nil
      allow(blob).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        winner ||= ActiveStorage::AsyncVariants.ensure_preview_image_placeholder!(ActiveStorage::Blob.find(blob.id))
        original.call(*args, &block)
      end

      loser = ActiveStorage::AsyncVariants.ensure_preview_image_placeholder!(blob)

      expect(winner).to be_present
      expect(loser).to eq(winner)
      expect(ActiveStorage::Attachment.where(record: blob, name: "preview_image").count).to eq(1)
    end

    it "reuses an already attached frame without creating another" do
      blob = video_blob
      first = ActiveStorage::AsyncVariants.ensure_preview_image_placeholder!(blob)

      expect {
        expect(ActiveStorage::AsyncVariants.ensure_preview_image_placeholder!(blob)).to eq(first)
      }.not_to change { ActiveStorage::Attachment.where(record: blob, name: "preview_image").count }
    end
  end

  describe "Preview#async_record" do
    it "is the record on the frame blob, or nil before any exists" do
      preview = @user.video.preview(:poster)
      expect(preview.async_record).to be_nil

      preview.enqueue!

      expect(@user.video.preview(:poster).async_record).to eq(video_blob.preview_image.blob.variant_records.sole)
    end
  end

  describe "Preview#retry! on a previewable blob" do
    it "replaces a failed frame record with a pending one and enqueues ProcessJob" do
      @user.video.preview(:poster).enqueue!
      failed = video_blob.preview_image.blob.variant_records.sole.tap { |r| r.update!(state: "failed", error: "boom") }

      expect {
        @user.video.preview(:poster).retry!
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)

      expect(ActiveStorage::VariantRecord.exists?(failed.id)).to be(false)
      expect(@user.video.preview(:poster).async_record.state).to eq("pending")
    end

    it "leaves a frame record that is not failed alone" do
      @user.video.preview(:poster).enqueue!
      pending = video_blob.preview_image.blob.variant_records.sole

      expect {
        @user.video.preview(:poster).retry!
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)

      expect(@user.video.preview(:poster).async_record).to eq(pending)
    end
  end

  describe "ProcessJob via the preview path (inline transformer)" do
    it "extracts a real frame with the stock previewer and processes the variant from it" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster_inline)

      frame = video_blob.preview_image.blob
      expect(frame.checksum).not_to eq("0")
      expect(frame.byte_size).to be > 0

      record = frame.variant_records.sole
      expect(record.state).to eq("processed")
      expect(record.image).to be_attached
    end
  end

  describe "auto-enqueue on attach" do
    it "enqueues ProcessJob for each async variant of the previewable blob" do
      poster_jobs = enqueued_jobs.select { |job|
        job[:job] == ActiveStorage::AsyncVariants::ProcessJob &&
          job[:args].last == "poster"
      }
      expect(poster_jobs.size).to eq(1)
    end
  end
end
