module Admin
  class UsersController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin
    before_action :set_user, only: [:show, :edit, :update, :destroy]
    layout 'admin'

    def index
      # Remove the includes(:courses) as suggested by Bullet
      @users = User.order(:role, :last_name)
      @passwords = User.where.not(seed_password: nil).pluck(:username, :seed_password).to_h
      
      # Add role-based user statistics
      @teachers = User.where(role: 'Teacher')
      @students = User.where(role: 'Student')
      
      # Add account status statistics for the modal
      @active_users = User.where(locked_at: nil)
      @locked_users = User.where.not(locked_at: nil)
      
      # Use updated_at instead of current_sign_in_at for activity statistics
      @active_today = User.where('updated_at > ?', 1.day.ago)
      @active_this_week = User.where('updated_at > ?', 1.week.ago)
    end

    def show
    end

    def new
      @user = User.new
    end

    def edit
    end

    def create
      @user = User.new(user_params)

      if @user.save
        redirect_to admin_users_path, notice: 'User was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @user.update(user_params)
        redirect_to admin_users_path, notice: 'User was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @user.destroy
      redirect_to admin_users_path, notice: 'User was successfully deleted.'
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email, :first_name, :last_name, :role, :password, :password_confirmation)
    end

    def ensure_admin
      unless current_user&.admin?
        redirect_to root_path, alert: 'Access denied. Admin only.'
      end
    end
  end
end