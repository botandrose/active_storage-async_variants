# frozen_string_literal: true

RSpec.describe "async variants: callback endpoint" do
  include_context "with an attached avatar"

  describe "callback endpoint", type: :request do
    it "transitions variant to processed on success callback" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "success", content_type: "image/webp", byte_size: 1234 },
        as: :json

      expect(response).to have_http_status(:ok)
      variant_record.reload
      expect(variant_record.state).to eq("processed")
    end

    it "applies the reported byte_size and checksum to the placeholder variant blob" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      placeholder = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "thumb.webp", content_type: "image/webp",
        service_name: "test", byte_size: 0, checksum: "0",
      )
      variant_record.image.attach(placeholder)
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "success", byte_size: 4567, checksum: "eM4lMR7iY0vWpgLrqBXddg==" },
        as: :json

      expect(response).to have_http_status(:ok)
      placeholder.reload
      expect(placeholder.byte_size).to eq(4567)
      expect(placeholder.checksum).to eq("eM4lMR7iY0vWpgLrqBXddg==")
    end

    it "applies preview_image byte_size and checksum to a zero-byte source blob (video frame)" do
      preview_blob = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "frame.jpg", content_type: "image/jpeg",
        service_name: "test", byte_size: 0, checksum: "0",
      )
      variant = @user.avatar.variant(:thumb)
      variant_record = preview_blob.variant_records.create!(
        variation_digest: variant.variation.digest, state: "processing",
      )
      variant_record.image.attach(
        ActiveStorage::Blob.create_before_direct_upload!(
          filename: "thumb.webp", content_type: "image/webp",
          service_name: "test", byte_size: 0, checksum: "0",
        ),
      )
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "success", byte_size: 4567, checksum: "QnQbhWqM4JDca/q1RCowig==",
                  preview_image_byte_size: 8910, preview_image_checksum: "h8arsBrB0ACLrhqOw723VQ==" },
        as: :json

      expect(response).to have_http_status(:ok)
      preview_blob.reload
      expect(preview_blob.byte_size).to eq(8910)
      expect(preview_blob.checksum).to eq("h8arsBrB0ACLrhqOw723VQ==")
    end

    it "does not clobber a source blob that already has real byte_size and checksum" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      original_size = @user.avatar.blob.byte_size
      original_checksum = @user.avatar.blob.checksum
      expect(original_size).to be > 0
      expect(original_checksum).not_to eq("0")
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "success", preview_image_byte_size: 999_999, preview_image_checksum: "nope==" },
        as: :json

      expect(response).to have_http_status(:ok)
      @user.avatar.blob.reload
      expect(@user.avatar.blob.byte_size).to eq(original_size)
      expect(@user.avatar.blob.checksum).to eq(original_checksum)
    end

    it "transitions variant to failed on failure callback" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "failed", error: "ffmpeg exited with status 1" },
        as: :json

      expect(response).to have_http_status(:ok)
      variant_record.reload
      expect(variant_record.state).to eq("failed")
      expect(variant_record.error).to eq("ffmpeg exited with status 1")
    end

    it "truncates an oversized error payload to fit the column" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "failed", error: "x" * 100_000 },
        as: :json

      expect(response).to have_http_status(:ok)
      variant_record.reload
      expect(variant_record.state).to eq("failed")
      expect(variant_record.error.length).to eq(16_000)
    end

    it "rejects requests with invalid tokens" do
      post "/active_storage/async_variants/callbacks/invalid-token",
        params: { status: "success" },
        as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "callback with unknown status", type: :request do
    it "returns unprocessable_entity" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "unknown" },
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
