# frozen_string_literal: true

require "active_storage/service/disk_service"

module ActiveStorage
  class Service::TestCloudService < Service::DiskService
    def bucket
      "test-bucket"
    end
  end
end
