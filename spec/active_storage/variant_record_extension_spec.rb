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
