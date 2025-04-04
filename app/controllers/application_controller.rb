class ApplicationController < ActionController::Base
  include ErrorHandler
  
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :authenticate_user!
  layout :layout_by_resource

  protected

  def current_user
    if super.is_a?(Array) && super.first.is_a?(Array)
      # If we got the Warden session key array, load the actual user
      User.find_by(id: super.first.first)
    else
      super
    end
  end

  def configure_permitted_parameters
    added_attrs = [:username, :email, :first_name, :last_name, :role, :password, :password_confirmation]
    devise_parameter_sanitizer.permit(:sign_up, keys: added_attrs)
    devise_parameter_sanitizer.permit(:account_update, keys: added_attrs)
  end

  def after_sign_in_path_for(resource)
    if resource.admin?
      admin_dashboard_path
    else
      stored_location_for(resource) || dashboard_path
    end
  end

  def after_sign_out_path_for(resource_or_scope)
    new_user_session_path
  end

  # Turbo requires 303 See Other status for redirects after DELETE
  def redirect_to(options = {}, response_status = {})
    if turbo_frame_request? || request.delete?
      response_status[:status] ||= :see_other
    end
    super(options, response_status)
  end

  def layout_by_resource
    if devise_controller?
      'devise'
    else
      'application'
    end
  end
end
