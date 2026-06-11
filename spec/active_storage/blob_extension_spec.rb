# frozen_string_literal: true

require "tmpdir"
require "active_storage/service/mirror_service"

RSpec.describe ActiveStorage::AsyncVariants::BlobExtension do
  include_context "with an attached avatar"

  let(:blob) { @user.avatar.blob }
  let(:bucket_service) { ActiveStorage::Service::TestCloudService.new(root: Dir.mktmpdir) }
  let(:disk_service) { ActiveStorage::Service::DiskService.new(root: Dir.mktmpdir) }

  describe "#bucket_backed?" do
    it "is true for a bucket-backed service" do
      expect(blob.bucket_backed?).to be true
    end

    it "is false for a disk service" do
      allow(blob).to receive(:service).and_return(disk_service)

      expect(blob.bucket_backed?).to be false
    end

    it "is true for a MirrorService whose primary is bucket-backed" do
      mirror = ActiveStorage::Service::MirrorService.new(primary: bucket_service, mirrors: [disk_service])
      allow(blob).to receive(:service).and_return(mirror)

      expect(blob.bucket_backed?).to be true
    end

    it "is false for a MirrorService whose primary is a disk service" do
      mirror = ActiveStorage::Service::MirrorService.new(primary: disk_service, mirrors: [disk_service])
      allow(blob).to receive(:service).and_return(mirror)

      expect(blob.bucket_backed?).to be false
    end
  end
end
