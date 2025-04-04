class PerformanceMetricsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:metrics]
  skip_before_action :authenticate_user!, only: [:metrics]
  before_action :verify_monitoring_token, only: [:metrics]
  before_action :authenticate_user!
  before_action :ensure_teacher

  def index
    @cache_metrics = fetch_cache_metrics
    @calculation_metrics = fetch_calculation_metrics
    @error_rates = fetch_error_rates
    @course_statistics = fetch_course_statistics
    @health_check_results = Rails.application.config.startup_check_results

    respond_to do |format|
      format.html
      format.json { render json: { metrics: @metrics, statistics: @course_statistics, health: @health_check_results } }
    end
  end

  def metrics
    data = collect_performance_metrics
    if stale?(etag: data[:timestamp], last_modified: Time.parse(data[:timestamp]))
      render json: data
    end
  end

  def health_check
    return head :unauthorized unless current_user&.teacher?

    StartupHealthCheckJob.perform_later
    flash[:notice] = "Health check initiated. Results will be available shortly."
    redirect_to performance_metrics_path
  end

  private

  def ensure_teacher
    unless current_user&.teacher?
      redirect_to root_path, alert: 'Access denied. Teachers only.'
    end
  end

  def fetch_cache_metrics
    today = Date.current.to_s
    total_hits = 0
    total_misses = 0

    # Use Redis directly through Rails.cache.redis to access the connection pool
    Rails.cache.redis.with do |redis|
      Course.find_each do |course|
        hits_key = "metrics:course:#{course.id}:cache_hits:#{today}"
        misses_key = "metrics:course:#{course.id}:cache_misses:#{today}"
        
        total_hits += redis.get(hits_key).to_i
        total_misses += redis.get(misses_key).to_i
      end
    end

    total = total_hits + total_misses
    rate = total.zero? ? 0 : ((total_hits.to_f / total) * 100).round(2)

    { hits: total_hits, misses: total_misses, rate: rate }
  end

  def fetch_calculation_metrics
    today = Date.current.to_s
    Course.includes(:grades).map do |course|
      avg_time = Rails.cache.read(
        "metrics:course:#{course.id}:daily_avg_calculation_time:#{today}"
      ).to_f

      {
        course_name: course.name,
        avg_calculation_time: avg_time,
        student_count: course.students.count
      }
    end.sort_by { |m| -m[:avg_calculation_time] }.first(10)
  end

  def fetch_error_rates
    pattern = "metrics:statistics_errors:*"
    error_keys = []
    
    Rails.cache.redis.with do |redis|
      error_keys = redis.keys(pattern)
    end
    
    error_keys.each_with_object(Hash.new(0)) do |key, counts|
      value = Rails.cache.read(key)
      next unless value

      tags = Rails.cache.read("#{key}:tags")
      next unless tags

      error_type = tags["error_type"]
      counts[error_type] += value.to_i
    end
  end

  def fetch_course_statistics
    Course.includes(:grades).map do |course|
      {
        name: course.name,
        calculation_time: fetch_course_calculation_time(course),
        cache_hit_rate: fetch_course_cache_rate(course)
      }
    end
  end

  def fetch_course_calculation_time(course)
    today = Date.current.to_s
    Rails.cache.read(
      "metrics:course:#{course.id}:daily_avg_calculation_time:#{today}"
    ).to_f
  end

  def fetch_course_cache_rate(course)
    today = Date.current.to_s
    hits = Rails.cache.read("metrics:course:#{course.id}:cache_hits:#{today}").to_i
    misses = Rails.cache.read("metrics:course:#{course.id}:cache_misses:#{today}").to_i
    total = hits + misses
    
    total.zero? ? 0 : ((hits.to_f / total) * 100).round(1)
  end

  def collect_performance_metrics
    {
      timestamp: Time.current.iso8601,
      cache: fetch_cache_metrics,
      calculations: fetch_calculation_metrics,
      errors: fetch_error_rates,
      database: collect_database_metrics,
      redis: collect_redis_metrics,
      jobs: collect_job_metrics
    }
  end

  def collect_database_metrics
    {
      active_connections: ActiveRecord::Base.connection_pool.connections.count(&:in_use?),
      pool_size: ActiveRecord::Base.connection_pool.size,
      waiting_connections: ActiveRecord::Base.connection_pool.num_waiting_in_queue
    }
  end

  def collect_redis_metrics
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
    info = redis.info

    {
      connected_clients: info["connected_clients"].to_i,
      used_memory_human: info["used_memory_human"],
      peak_memory_human: info["used_memory_peak_human"],
      total_commands: info["total_commands_processed"].to_i
    }
  rescue Redis::CannotConnectError => e
    Rails.logger.error("Failed to connect to Redis: #{e.message}")
    {
      error: "Could not connect to Redis",
      connected_clients: 0,
      used_memory_human: "N/A",
      peak_memory_human: "N/A",
      total_commands: 0
    }
  end

  def collect_job_metrics
    {
      enqueued: SolidQueue::Job.joins(:ready_execution).count,
      scheduled: SolidQueue::Job.joins(:scheduled_execution).count,
      failed: SolidQueue::FailedExecution.count,
      active_processes: SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).count
    }
  end

  def verify_monitoring_token
    unless request.headers["X-Monitoring-Token"] == ENV["MONITORING_TOKEN"]
      head :unauthorized
    end
  end
end