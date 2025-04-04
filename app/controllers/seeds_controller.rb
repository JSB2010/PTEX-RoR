class AdminController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :authenticate_admin, except: :update_admin
  
  def dashboard
    @teachers = User.includes(:courses).where(role: 'Teacher').order(:last_name)
    @students = User.where(role: 'Student').order(:last_name)
    @courses = Course.includes(:teacher, :grades).order(:name)
    @total_users = User.count
    @total_courses = Course.count
    @total_grades = Grade.count
    
    # System stats
    @redis_status = redis_status
    @sidekiq_status = sidekiq_status
    @db_status = database_status
  end

  def users
    @users = User.includes(:courses).order(:role, :last_name)
    @passwords = User.where.not(seed_password: nil).pluck(:username, :seed_password).to_h
  end

  def courses
    @courses = Course.includes(:teacher, :students, :grades)
                    .order(:name)
  end

  def system
    @ruby_version = RUBY_VERSION
    @rails_version = Rails::VERSION::STRING
    @database_size = ActiveRecord::Base.connection.execute("SELECT pg_size_pretty(pg_database_size(current_database()));").first["pg_size_pretty"]
    @cache_stats = Rails.cache.stats
    @job_stats = SolidQueue::Job.group(:queue_name).count
  end

  def update_admin
    old_credentials = get_admin_credentials
    
    if params[:old_username] == old_credentials[:username] && 
       params[:old_password] == old_credentials[:password]
      
      new_credentials = {
        username: params[:new_username],
        password: params[:new_password]
      }
      
      Rails.cache.write('admin_credentials', new_credentials)
      flash[:notice] = 'Admin credentials updated successfully'
    else
      flash[:alert] = 'Current credentials are incorrect'
    end

    redirect_to admin_dashboard_path
  end

  def cleanup_data
    Grade.where('created_at < ?', 1.year.ago).delete_all
    Course.where('created_at < ? AND students_count = 0', 6.months.ago).delete_all
    
    flash[:notice] = 'Old data cleaned up successfully'
    redirect_to admin_dashboard_path
  end

  private

  def authenticate_admin
    credentials = get_admin_credentials
    authenticate_or_request_with_http_basic do |username, password|
      username == credentials[:username] && password == credentials[:password]
    end
  end

  def get_admin_credentials
    Rails.cache.fetch('admin_credentials') do
      { username: 'admin', password: 'ptexadmin2024' }
    end
  end

  def redis_status
    Redis.current.ping == 'PONG'
  rescue
    false
  end

  def sidekiq_status
    Sidekiq::ProcessSet.new.size.positive?
  rescue
    false
  end

  def database_status
    ActiveRecord::Base.connection.active?
  rescue
    false
  end
end