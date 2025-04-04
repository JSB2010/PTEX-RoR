module Admin
  class AdminController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin
    layout 'admin'
    
    def index
      @teachers = User.includes(:courses).where(role: 'Teacher').order(:last_name)
      @students = User.where(role: 'Student').order(:last_name)
      @courses = Course.includes(:teacher).order(:name)
      @total_users = User.count
      @total_courses = Course.count
      @total_grades = Grade.count
      
      # System stats
      @redis_status = redis_status
      @background_job_status = background_job_status
      @db_status = database_status
    end

    # Removed the users action as it's now handled by Admin::UsersController

    def courses
      @courses = Course.includes(:teacher, :students, :grades)
                      .order(:name)
    end

    def students
      course = Course.includes(grades: :user).find(params[:id])
      students = course.grades.map do |grade|
        {
          name: grade.user.full_name,
          email: grade.user.email,
          grade: grade.letter_grade,
          grade_class: grade_badge_class(grade.letter_grade),
          updated_at: grade.updated_at.strftime("%B %d, %Y")
        }
      end

      render json: { students: students }
    end

    def system
      @ruby_version = RUBY_VERSION
      @rails_version = Rails::VERSION::STRING
      @database_size = ActiveRecord::Base.connection.execute("SELECT pg_size_pretty(pg_database_size(current_database()));").first["pg_size_pretty"]
      
      # Get Redis stats safely
      @cache_stats = begin
        if Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore)
          $redis.with do |conn|
            info = conn.info
            {
              'Connected Clients': info['connected_clients'],
              'Memory Used': info['used_memory_human'],
              'Peak Memory': info['used_memory_peak_human'],
              'Uptime (days)': info['uptime_in_days']
            }
          end
        else
          {}
        end
      rescue => e
        Rails.logger.error("Failed to collect cache stats: #{e.message}")
        {}
      end

      # Get job stats and handle nil queue_names
      @job_stats = SolidQueue::Job
        .group(:queue_name)
        .count
        .transform_keys { |k| k.presence || 'default' }
      
      # System status
      @redis_status = redis_status
      @background_job_status = background_job_status
      @db_status = database_status

      respond_to do |format|
        format.html
        format.json do
          render json: {
            ruby_version: @ruby_version,
            rails_version: @rails_version,
            database_size: @database_size,
            redis_status: @redis_status,
            background_job_status: @background_job_status,
            db_status: @db_status,
            cache_stats: @cache_stats,
            job_stats: @job_stats,
            last_update: Time.current
          }
        end
      end
    end

    def cleanup_data
      CleanupOldDataJob.perform_later(
        grades: true,
        courses: true,
        cache: true,
        jobs: true,
        grade_age: 1.year.ago,
        course_age: 6.months.ago,
        job_age: 1.month.ago
      )
      
      flash[:notice] = 'Cleanup job has been scheduled'
      redirect_to admin_system_path
    end

    def clear_cache
      Rails.cache.clear
      
      respond_to do |format|
        format.html do
          flash[:notice] = 'Cache cleared successfully'
          redirect_to admin_system_path
        end
        format.json do
          render json: { status: 'success', message: 'Cache cleared successfully' }
        end
      end
    end

    def download_logs
      send_file(
        Rails.root.join('log', "#{Rails.env}.log"),
        filename: "#{Rails.env}-#{Time.current.strftime('%Y%m%d%H%M%S')}.log",
        type: 'text/plain'
      )
    end

    def cleanup_logs
      CleanupLogsJob.perform_later
      
      respond_to do |format|
        format.html do
          flash[:notice] = 'Log cleanup job has been scheduled'
          redirect_to admin_system_path
        end
        format.json do
          render json: { status: 'success', message: 'Log cleanup job has been scheduled' }
        end
      end
    end

    def lock_user
      user = User.find(params[:id])
      user.lock_access!
      redirect_to admin_users_path, notice: "User #{user.email} has been locked"
    end

    def unlock_user
      user = User.find(params[:id])
      user.unlock_access!
      redirect_to admin_users_path, notice: "User #{user.email} has been unlocked"
    end

    private

    def ensure_admin
      unless current_user&.admin?
        respond_to do |format|
          format.html { redirect_to root_path, alert: 'You must be an administrator to access this area.' }
          format.json { render json: { error: 'Unauthorized' }, status: :unauthorized }
        end
      end
    end

    def redis_status
      $redis.with { |conn| conn.ping == 'PONG' }
    rescue
      false
    end

    def background_job_status
      # Check for both workers and dispatchers within heartbeat window
      SolidQueue::Process.where("last_heartbeat_at >= ?", 30.seconds.ago)
                        .where(kind: ['worker', 'dispatcher'])
                        .exists?
    rescue
      false
    end

    def database_status
      ActiveRecord::Base.connection.active?
    rescue
      false
    end

    def grade_badge_class(grade)
      case grade
      when 'A' then 'success'
      when 'B' then 'primary'
      when 'C' then 'warning'
      when 'D', 'F' then 'danger'
      else 'secondary'
      end
    end
  end
end