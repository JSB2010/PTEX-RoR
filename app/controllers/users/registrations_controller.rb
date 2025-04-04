class Users::RegistrationsController < Devise::RegistrationsController
  prepend_view_path 'app/views/devise'
  
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]

  # Override the create method to handle our custom attributes
  def create
    super do |resource|
      if resource.persisted?
        if resource.active_for_authentication?
          set_flash_message! :notice, :signed_up
        else
          set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        end
      end
    end
  end

  protected

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :username, :role])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :username])
  end

  def after_sign_up_path_for(resource)
    dashboard_path
  end

  def after_update_path_for(resource)
    edit_user_registration_path
  end

  def update_resource(resource, params)
    # If password is provided, update password
    if params[:password].present?
      resource.update_with_password(params)
    else
      # Remove password keys if password is not being updated
      params.delete(:password)
      params.delete(:password_confirmation)
      params.delete(:current_password)
      
      resource.update_without_password(params)
    end
  end

  private

  def sign_up_params
    params.require(:user).permit(:first_name, :last_name, :username, :email, :role, :password, :password_confirmation)
  end

  def account_update_params
    params.require(:user).permit(:first_name, :last_name, :username, :email, :password, :password_confirmation, :current_password)
  end
end