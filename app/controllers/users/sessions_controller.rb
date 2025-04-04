class Users::SessionsController < Devise::SessionsController
  # Override create to handle sign in
  def create
    super do |resource|
      if resource.persisted?
        redirect_path = after_sign_in_path_for(resource)
        return redirect_to redirect_path
      end
    end
  end

  # Override destroy to handle sign out
  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    set_flash_message! :notice, :signed_out if signed_out
    yield if block_given?
    
    respond_to do |format|
      format.html { redirect_to after_sign_out_path_for(resource_name), status: :see_other }
      format.json { head :no_content }
      format.any { head :no_content }
    end
  end

  protected

  def after_sign_in_path_for(resource)
    if resource.admin?
      admin_dashboard_path
    elsif resource.teacher?
      dashboard_path
    else # student
      dashboard_path
    end
  end

  def after_sign_out_path_for(resource_or_scope)
    new_user_session_path
  end

  def auth_options
    { scope: resource_name, recall: "#{controller_path}#new" }
  end
end