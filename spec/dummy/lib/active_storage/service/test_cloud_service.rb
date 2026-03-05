# frozen_string_literal: true

require "active_storage/service/disk_service"

module ActiveStorage
  class Service::TestCloudService < Service::DiskService
    def is_a?(klass)
      return false if klass == Service::DiskService
      super
    end
  end
end
