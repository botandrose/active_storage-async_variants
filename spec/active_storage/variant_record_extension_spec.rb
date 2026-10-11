# frozen_string_literal: true

RSpec.describe "async variants: VariantRecord terminal-state cache busting" do
  include_context "with an attached avatar"

  describe "touching attached records when variant reaches a terminal state" do
    it "touches the attachment's record when state transitions to processed" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")

      expect { variant_record.update!(state: "processed") }
        .to change { @user.reload.updated_at }
    end

    it "touches the attachment's record when state transitions to failed" do
      # Failed is also terminal: cached fragments built while the state was
      # pending/processing need to be invalidated so the next render sees it.
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")

      expect { variant_record.update!(state: "failed", error: "boom") }
        .to change { @user.reload.updated_at }
    end

    it "does not touch records on intermediate state transitions" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "pending")

      expect { variant_record.update!(state: "processing") }
        .not_to change { @user.reload.updated_at }
    end

    it "does not touch records when state is unchanged" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processed")

      expect { variant_record.update!(error: "no-op") }
        .not_to change { @user.reload.updated_at }
    end
  end
end

RSpec.describe "async variants: purging a source blob mid-render" do
  include_context "with an attached avatar"

  it "leaves no output attached to a variant record its purge destroyed" do
    record = create_variant_record(@user.avatar.variant(:thumb), state: "processing")
    output = ActiveStorage::Blob.create_before_direct_upload!(filename: "image.webp", content_type: "image/webp", byte_size: 0, checksum: "0")
    # The purge reads the record's output, then a render commits one while the purge waits on the row lock.
    allow_any_instance_of(ActiveStorage::VariantRecord).to receive(:destroy).and_wrap_original do |destroy|
      destroy.receiver.image_attachment
      ActiveStorage::Attachment.insert!({ name: "image", record_type: "ActiveStorage::VariantRecord", record_id: record.id, blob_id: output.id, created_at: Time.current })
      destroy.call
    end

    perform_enqueued_jobs { @user.avatar.purge }

    expect(ActiveStorage::Attachment.where(record_type: "ActiveStorage::VariantRecord")).to be_empty
    expect(ActiveStorage::Blob.exists?(output.id)).to be(false)
  end
end
