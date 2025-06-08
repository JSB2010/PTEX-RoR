class StatusController < ActionController::Base
  # Skip authentication for status pages
  skip_before_action :authenticate_user!, if: :skip_auth?
  
  def index
    if database_available?
      redirect_to root_path
    else
      render :deployment_status, layout: 'status'
    end
  end
  
  def deployment_status
    @database_status = database_available?
    @redis_status = redis_available?
    render layout: 'status'
  end
  
  private
  
  def skip_auth?
    ENV['VERCEL_DEPLOYMENT'] == 'true' || !database_available?
  end
  
  def database_available?
    @database_available ||= begin
      ActiveRecord::Base.connection.active?
    rescue StandardError
      false
    end
  end
  
  def redis_available?
    @redis_available ||= begin
      Rails.cache.redis.ping == 'PONG'
    rescue StandardError
      false
    end
  end
end
