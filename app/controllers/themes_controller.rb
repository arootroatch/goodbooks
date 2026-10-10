class ThemesController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_household

  def update
    if Theme::CHOICES.include?(params[:theme])
      cookies[Theme::COOKIE] = { value: params[:theme], expires: 1.year, same_site: :lax }
    end
    redirect_back_or_to root_path
  end
end
