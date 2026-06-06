class AvatarsController < ApplicationController
  # GET /avatars/:user_id/:variant_name
  # Renders a page with image_tag for the given variant, the way a real
  # consumer would. Drives the gem's image_tag/video_tag extension end-to-end.
  def show
    @user = User.find(params[:user_id])
    @variant_name = params[:variant_name].to_sym
    @variant = @user.avatar.variant(@variant_name) # used by show.html.erb; do not strip
    render :show
  end
end
