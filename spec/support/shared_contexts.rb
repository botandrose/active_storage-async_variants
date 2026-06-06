# frozen_string_literal: true

RSpec.shared_context "with an attached avatar" do
  before do
    @user = User.create!
    @user.avatar.attach(
      io: File.open("spec/support/fixtures/image.png"),
      filename: "image.png",
      content_type: "image/png",
    )
  end
end
