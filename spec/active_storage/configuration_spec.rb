# frozen_string_literal: true

RSpec.describe "async variants: configuration" do
  around do |example|
    previous = ActiveStorage::AsyncVariants.cdn_host
    example.run
    ActiveStorage::AsyncVariants.cdn_host = previous
  end

  it "yields the module so options can be set in one block" do
    ActiveStorage::AsyncVariants.configure do |config|
      config.cdn_host = "https://cdn.example.com"
    end

    expect(ActiveStorage::AsyncVariants.cdn_host).to eq("https://cdn.example.com")
  end
end
