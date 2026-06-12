# frozen_string_literal: true

RSpec.describe "async variants: progress reporting" do
  include_context "with an attached avatar"

  describe "progress query API on VariantWithRecord" do
    it "reports nil progress and unknown before any heartbeat" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "processing")

      expect(variant.progress).to be_nil
      expect(variant.progress_known?).to be false
      expect(variant.last_heartbeat_at).to be_nil
    end

    it "reports the recorded progress and heartbeat" do
      variant = @user.avatar.variant(:thumb)
      record = create_variant_record(variant, state: "processing")
      heartbeat = Time.current.change(usec: 0)
      record.update!(progress: 42, last_heartbeat_at: heartbeat)

      expect(variant.progress).to eq(42)
      expect(variant.progress_known?).to be true
      expect(variant.last_heartbeat_at).to eq(heartbeat)
    end

    it "reports a progress rate of percent over elapsed processing time" do
      variant = @user.avatar.variant(:thumb)
      record = create_variant_record(variant, state: "processing")
      base = Time.current
      record.update!(progress: 42, created_at: base - 84, last_heartbeat_at: base)

      expect(variant.progress_rate).to eq(0.5)
    end

    it "reports a nil rate before any progress" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "processing")

      expect(variant.progress_rate).to be_nil
    end
  end

  describe "progress query API on Preview" do
    before { attach_video_to(@user) }

    let(:preview) { @user.video.preview(:poster) }

    def create_frame_record
      ActiveStorage::AsyncVariants.ensure_preview_image_placeholder!(@user.video.blob)
      create_variant_record(preview.send(:variant), state: "processing")
    end

    it "reports nil progress and unknown before any heartbeat" do
      create_frame_record

      expect(preview.progress).to be_nil
      expect(preview.progress_known?).to be false
      expect(preview.last_heartbeat_at).to be_nil
    end

    it "reports the recorded progress and heartbeat" do
      record = create_frame_record
      heartbeat = Time.current.change(usec: 0)
      record.update!(progress: 73, last_heartbeat_at: heartbeat)

      expect(preview.progress).to eq(73)
      expect(preview.progress_known?).to be true
      expect(preview.last_heartbeat_at).to eq(heartbeat)
    end
  end
end
