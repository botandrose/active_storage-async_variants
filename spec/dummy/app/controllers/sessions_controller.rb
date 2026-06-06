class SessionsController < ApplicationController
  # Minimal "login" for cucumber: GET-able so step defs can use Capybara `visit`.
  def show
    session[:user_id] = params[:user_id].to_i
    head :ok
  end

  def destroy
    session.delete(:user_id)
    head :no_content
  end
end
