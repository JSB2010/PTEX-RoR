require 'net/http'

class StartupCheckService
  def self.run
    new.perform_checks
  end

  def perform_checks
    {
      server_status: check_server_status,
      service_checks: check_critical_services,
      database_checks: check_database_details
    }
  end

  private

  def check_server_status
    response = Net::HTTP.get_response(URI.parse(health_check_url))
    {
      status: response.code == '200' ? 'success' : 'error',
      message: "Server responded with status #{response.code}",
      response_time: measure_response_time
    }
  rescue => e
    { status: 'error', message: "Server error: #{e.message}" }
  end

  def check_critical_services
    {
      redis: check_redis_connection,
      database: check_database_connection,
      job_system: check_job_system
    }
  end

  def check_redis_connection
    Redis.current.ping == 'PONG'
    { status: 'success', message: 'Redis connection successful' }
  rescue => e
    { status: 'error', message: "Redis error: #{e.message}" }
  end

  def check_database_connection
    ActiveRecord::Base.connection.active?
    { status: 'success', message: 'Database connection successful' }
  rescue => e
    { status: 'error', message: "Database error: #{e.message}" }
  end

  def check_job_system
    # Check for SolidQueue processes
    if defined?(SolidQueue::Process)
      workers = SolidQueue::Process.where(kind: "Worker")
                                 .or(SolidQueue::Process.where(kind: "DirectWorker"))
                                 .where("last_heartbeat_at > ?", 5.minutes.ago)
                                 .count
      
      # Also check for pending jobs
      pending_jobs = SolidQueue::Job.where(finished_at: nil).count
      
      if workers > 0
        { 
          status: 'success', 
          message: "SolidQueue operational with #{workers} active workers",
          details: { workers: workers, pending_jobs: pending_jobs }
        }
      else
        { 
          status: 'warning', 
          message: 'No active SolidQueue workers found',
          details: { workers: 0, pending_jobs: pending_jobs }
        }
      end
    else
      # SolidQueue may not be loaded yet
      { status: 'warning', message: 'SolidQueue not initialized' }
    end
  rescue => e
    { status: 'error', message: "Job system error: #{e.message}" }
  end

  def check_database_details
    return nil unless ActiveRecord::Base.connection.active?

    pool = {
      size: ActiveRecord::Base.connection_pool.size,
      active: ActiveRecord::Base.connection_pool.connections.count(&:in_use?),
      waiting: ActiveRecord::Base.connection_pool.num_waiting_in_queue
    }

    # Gather table statistics
    tables = {}
    if defined?(ActiveRecord::Base) && Rails.env.development?
      begin
        # Get a few important tables
        key_tables = ['users', 'solid_queue_jobs', 'solid_queue_ready_executions']
        key_tables.each do |table|
          if ActiveRecord::Base.connection.table_exists?(table)
            count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table}").first['count']
            tables[table] = { 
              rows: count,
              size: format_size(estimated_table_size(table))
            }
          end
        end
      rescue => e
        Rails.logger.error("Error gathering table stats: #{e.message}")
      end
    end

    { status: 'success', pool: pool, tables: tables }
  rescue => e
    { status: 'error', message: "Database details error: #{e.message}" }
  end

  def estimated_table_size(table_name)
    result = ActiveRecord::Base.connection.execute(
      "SELECT pg_total_relation_size($1) AS size",
      [table_name]
    ).first
    result['size'].to_i
  rescue => e
    Rails.logger.error("Error getting table size: #{e.message}")
    0
  end

  def format_size(bytes)
    return "0 B" if bytes == 0
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = [exp, units.size - 1].min
    format("%.1f %s", (bytes.to_f / 1024 ** exp), units[exp])
  end

  def measure_response_time
    start_time = Time.now
    Net::HTTP.get(URI.parse(health_check_url))
    (Time.now - start_time).round(2)
  rescue
    nil
  end

  def health_check_url
    "http://localhost:#{port}/health"
  end

  def port
    ENV.fetch('PORT', 3000)
  end
end