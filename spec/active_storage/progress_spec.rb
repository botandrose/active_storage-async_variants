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
  end

  describe "progress query API on Preview" do
    let(:blob) { @user.avatar.blob }

    it "reports nil progress and unknown before any heartbeat" do
      named_variant = @user.avatar.variant(:thumb_preview)
      create_variant_record(named_variant, state: "processing")
      preview = ActiveStorage::Preview.new(blob, named_variant.variation)

      expect(preview.progress).to be_nil
      expect(preview.progress_known?).to be false
      expect(preview.last_heartbeat_at).to be_nil
    end

    it "reports the recorded progress and heartbeat" do
      named_variant = @user.avatar.variant(:thumb_preview)
      record = create_variant_record(named_variant, state: "processing")
      heartbeat = Time.current.change(usec: 0)
      record.update!(progress: 73, last_heartbeat_at: heartbeat)
      preview = ActiveStorage::Preview.new(blob, named_variant.variation)

      expect(preview.progress).to eq(73)
      expect(preview.progress_known?).to be true
      expect(preview.last_heartbeat_at).to eq(heartbeat)
    end
  end
end
