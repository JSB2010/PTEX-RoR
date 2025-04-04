# frozen_string_literal: true
require 'socket'
require 'net/http'
require 'resolv'
require 'find'

class HealthController < ApplicationController
  # Skip authentication for health checks
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:queue_status]

  def index
    @health_data = {
      status: "ok",
      timestamp: Time.current.utc.iso8601,
      ruby_version: RUBY_VERSION,
      rails_version: Rails::VERSION::STRING,
      environment: Rails.env,
      database: database_health,
      redis: redis_health,
      job_system: job_system_health,
      memory: memory_stats,
      system: system_info,
      disk: disk_stats,
      network: network_stats,
      request_stats: request_statistics,
      errors: error_summary,
      dependencies: dependency_status
    }

    # Collect issues that need attention
    @health_data[:issues] = collect_issues

    # Generate a summary of the system health
    @health_data[:summary] = generate_summary

    # Update overall status if any subsystem is not healthy
    @health_data[:status] = "error" if [
      @health_data[:database][:connected],
      @health_data[:redis][:connected],
      @health_data[:job_system][:status] == "ok"
    ].include?(false) || @health_data[:job_system][:status].nil?

    # Set warning status if there are issues but no critical errors
    @health_data[:status] = "warning" if @health_data[:status] == "ok" && @health_data[:issues].any?

    # Add diagnostic details to the response
    @health_data[:diagnostic_summary] = @health_data[:summary][:diagnostic_details]

    # Detect if the request is coming from a browser or curl/API client
    is_browser_request = browser_request?

    # Log the request type for debugging
    Rails.logger.info "Health check request from #{is_browser_request ? 'browser' : 'API/curl'}"

    respond_to do |format|
      format.html do
        if is_browser_request
          # Render the HTML view for browsers
          render :index
        else
          # For curl or other non-browser clients requesting HTML, render JSON
          render json: @health_data
        end
      end
      format.json { render json: @health_data }
      format.any { render json: @health_data }
    end
  end

  # Determine if the request is coming from a browser
  def browser_request?
    user_agent = request.user_agent.to_s.downcase
    accept_header = request.headers['Accept'].to_s.downcase

    # Check if the user agent looks like a browser
    browser_agents = ['mozilla', 'webkit', 'chrome', 'safari', 'firefox', 'edge', 'opera']
    is_browser_agent = browser_agents.any? { |agent| user_agent.include?(agent) }

    # Check if the accept header prefers HTML
    prefers_html = accept_header.include?('text/html')

    # Check if it's a CLI tool
    is_cli_tool = user_agent.include?('curl') || user_agent.include?('wget') || user_agent.include?('httpie')

    # Log the detection for debugging
    Rails.logger.debug "User-Agent: #{user_agent}, Accept: #{accept_header}, Browser: #{is_browser_agent}, Prefers HTML: #{prefers_html}, CLI Tool: #{is_cli_tool}"

    # Return true if it looks like a browser request
    is_browser_agent && prefers_html && !is_cli_tool
  end

  def dashboard
    # Get the same health data as the index action
    index

    # Render the dashboard template
    render :dashboard
  end

  def queue_status
    queue_health = {
      healthy: SolidQueue.healthy?,
      processes: process_status,
      queues: queue_metrics,
      job_statistics: job_stats,
      timestamp: Time.current
    }

    if queue_health[:healthy]
      render json: queue_health
    else
      render json: queue_health, status: :service_unavailable
    end
  end

  private

  def system_info
    {
      hostname: Socket.gethostname,
      uptime: system_uptime,
      load_average: system_load_average,
      cpu_usage: cpu_usage,
      process_info: {
        pid: Process.pid,
        uptime: process_uptime,
        memory_usage: memory_usage,
        threads: Thread.list.count,
        open_files: count_open_files,
        environment_variables: filtered_env_vars
      },
      ruby_info: {
        gc_enabled: GC.enable,
        thread_abort_on_exception: Thread.abort_on_exception,
        loaded_gems: top_loaded_gems
      }
    }
  rescue StandardError => e
    {
      error: e.message
    }
  end

  def system_uptime
    uptime_seconds = if File.exist?('/proc/uptime')
                      File.read('/proc/uptime').split.first.to_f
                    elsif RUBY_PLATFORM =~ /darwin/
                      `sysctl -n kern.boottime`.scan(/\d+/).first.to_i
                      Time.now.to_i - $&.to_i
                    else
                      nil
                    end

    return "Unknown" unless uptime_seconds

    days = (uptime_seconds / 86400).floor
    hours = ((uptime_seconds % 86400) / 3600).floor
    minutes = ((uptime_seconds % 3600) / 60).floor

    "#{days}d #{hours}h #{minutes}m"
  end

  def system_load_average
    if File.exist?('/proc/loadavg')
      File.read('/proc/loadavg').split[0..2].map(&:to_f)
    elsif RUBY_PLATFORM =~ /darwin/
      `sysctl -n vm.loadavg`.scan(/\d+\.\d+/).map(&:to_f)
    else
      [0, 0, 0] # Default if can't determine
    end
  rescue
    [0, 0, 0]
  end

  def process_uptime
    process_start = File.stat("/proc/#{Process.pid}").ctime rescue Time.now - 30
    seconds = (Time.now - process_start).to_i

    hours = (seconds / 3600).floor
    minutes = ((seconds % 3600) / 60).floor

    "#{hours}h #{minutes}m"
  end

  def memory_usage
    if File.exist?("/proc/#{Process.pid}/status")
      mem_info = File.read("/proc/#{Process.pid}/status").match(/VmRSS:\s+(\d+)\s+kB/)
      mem_info ? "#{(mem_info[1].to_i / 1024.0).round(2)} MB" : "Unknown"
    else
      "#{(GetProcessMem.new.mb).round(2)} MB" rescue "Unknown"
    end
  end

  def database_health
    conn = ActiveRecord::Base.connection
    config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary").configuration_hash
    db_size = get_database_size

    # Get connection count
    active_connections = ActiveRecord::Base.connection_pool.connections.count(&:in_use?)
    pool_size = ActiveRecord::Base.connection_pool.size
    connection_percentage = (active_connections.to_f / pool_size) * 100

    # Determine status based on connection usage
    status = if connection_percentage > 90
               'warning'
             else
               'ok'
             end

    {
      connected: true,
      status: status,
      adapter: config[:adapter],
      pool_size: pool_size,
      active_connections: active_connections,
      connection_percentage: connection_percentage.round(1),
      waiting_in_queue: ActiveRecord::Base.connection_pool.num_waiting_in_queue,
      database_size: db_size,
      version: get_database_version
    }
  rescue StandardError => e
    {
      connected: false,
      status: 'error',
      error: e.message
    }
  end

  def redis_health
    redis = Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" })
    info = redis.info.transform_keys(&:to_sym)

    # Determine status based on client count
    client_count = info[:connected_clients].to_i

    status = if client_count > 100
               'warning'
             else
               'ok'
             end

    {
      connected: true,
      status: status,
      version: info[:redis_version],
      used_memory: info[:used_memory_human],
      clients: info[:connected_clients],
      uptime_days: info[:uptime_in_days]
    }
  rescue StandardError => e
    {
      connected: false,
      status: 'error',
      error: e.message
    }
  end

  def job_system_health
    begin
      # Get the configured adapter
      adapter = Rails.configuration.active_job.queue_adapter.to_s rescue 'unknown'

      # Default response for when SolidQueue is not available
      default_response = {
        adapter: adapter,
        status: "warning",
        error: "SolidQueue not available",
        queues: nil,
        active_workers: nil,
        dispatcher_running: nil,
        recent_jobs: { completed: 0, failed: 0, pending: 0 },
        auto_start: Rails.env.development?
      }

      # Check if SolidQueueManager is defined
      unless defined?(SolidQueueManager)
        Rails.logger.warn "SolidQueueManager is not defined"
        return default_response
      end

      # Check if database is connected
      unless ActiveRecord::Base.connected?
        Rails.logger.warn "Database is not connected, can't check job system health"
        return default_response.merge(error: "Database not connected")
      end

      # Check if SolidQueue tables exist
      begin
        unless ActiveRecord::Base.connection.table_exists?("solid_queue_processes")
          Rails.logger.warn "SolidQueue tables don't exist"
          return default_response.merge(error: "SolidQueue tables not found")
        end
      rescue => e
        Rails.logger.error "Error checking SolidQueue tables: #{e.message}"
        return default_response.merge(error: "Error checking SolidQueue tables: #{e.message}")
      end

      # Use SolidQueueManager to get status
      status = SolidQueueManager.status

      # Check if we need to start SolidQueue
      if status[:status] == "warning" && Rails.env.development? &&
         (!status[:disk_space] || !status[:disk_space][:warning]) &&
         (!status[:pg_connections] || !status[:pg_connections][:warning])
        # Try to start SolidQueue in development mode
        Thread.new do
          begin
            Rails.logger.info "Attempting to start SolidQueue from health check..."
            SolidQueueManager.initialize_solid_queue
          rescue => e
            Rails.logger.error "Failed to start SolidQueue: #{e.message}"
          end
        end
      end

      # Build the response
      result = {
        adapter: adapter,
        status: status[:status],
        queues: status[:queues],
        active_workers: status[:active_workers],
        dispatcher_running: status[:dispatcher_running],
        recent_jobs: recent_jobs_stats,
        auto_start: Rails.env.development?
      }

      # Add disk space info if present
      if status[:disk_space]
        result[:disk_space] = status[:disk_space]
      end

      # Add PostgreSQL connection info if present
      if status[:pg_connections]
        result[:pg_connections] = status[:pg_connections]
      end

      # Add PostgreSQL optimization recommendations if in development mode
      if Rails.env.development?
        result[:pg_recommendations] = PostgresConnectionManager.optimize_postgres_config
      end

      result
    rescue ActiveRecord::StatementInvalid, PG::ConnectionBad => e
      # Handle database connection issues
      {
        adapter: Rails.configuration.active_job.queue_adapter.to_s,
        status: "warning",
        error: "Database connection issue: #{e.message}",
        error_backtrace: Rails.env.development? ? e.backtrace.first(5) : nil,
        queues: [],
        active_workers: 0,
        dispatcher_running: false,
        recent_jobs: { completed: 0, failed: 0, pending: 0 },
        auto_start: false,
        recommendations: [
          "Run 'brew services restart postgresql@14' to restart PostgreSQL",
          "Check PostgreSQL logs for errors",
          "Consider upgrading to PostgreSQL 15 or 16 for better connection handling",
          "Reduce connection pool size in database.yml",
          "Set prepared_statements: false in database.yml"
        ]
      }
    rescue StandardError => e
      {
        adapter: Rails.configuration.active_job.queue_adapter.to_s,
        status: "error",
        error: e.message,
        error_backtrace: Rails.env.development? ? e.backtrace.first(5) : nil,
        queues: [],
        active_workers: 0,
        dispatcher_running: false,
        recent_jobs: { completed: 0, failed: 0, pending: 0 },
        auto_start: false
      }
    end
  end

  def recent_jobs_stats
    {
      completed: SolidQueue::Job.where.not(finished_at: nil)
                               .where("finished_at > ?", 1.hour.ago).count,
      failed: SolidQueue::FailedExecution.where("created_at > ?", 1.hour.ago).count,
      pending: SolidQueue::Job.where(finished_at: nil).count
    }
  rescue StandardError => e
    { error: e.message }
  end

  def memory_stats
    {
      total_allocated: GC.stat[:total_allocated_objects],
      total_freed: GC.stat[:total_freed_objects],
      heap_available: GC.stat[:heap_available_slots],
      heap_live: GC.stat[:heap_live_slots],
      gc_count: GC.count
    }
  end

  def get_database_size
    case ActiveRecord::Base.connection.adapter_name.downcase
    when 'postgresql'
      result = ActiveRecord::Base.connection.execute(
        "SELECT pg_size_pretty(pg_database_size(current_database()))"
      ).first["pg_size_pretty"]
      result
    when 'mysql', 'mysql2'
      result = ActiveRecord::Base.connection.execute(
        "SELECT SUM(data_length + index_length) / 1024 / 1024 FROM information_schema.TABLES WHERE table_schema = '#{ActiveRecord::Base.connection.current_database}'"
      ).first[0]
      "#{result.to_f.round(2)} MB"
    when 'sqlite', 'sqlite3'
      db_file = ActiveRecord::Base.connection.pool.spec.config[:database]
      "#{(File.size(db_file).to_f / 1024 / 1024).round(2)} MB" rescue "Unknown"
    else
      "Unknown"
    end
  rescue
    "Unknown"
  end

  def get_database_version
    case ActiveRecord::Base.connection.adapter_name.downcase
    when 'postgresql'
      ActiveRecord::Base.connection.execute("SELECT version()").first["version"]
    when 'mysql', 'mysql2'
      ActiveRecord::Base.connection.execute("SELECT version()").first[0]
    when 'sqlite', 'sqlite3'
      ActiveRecord::Base.connection.execute("SELECT sqlite_version()").first[0]
    else
      "Unknown"
    end
  rescue
    "Unknown"
  end

  def disk_stats
    disks = {}

    # Define system volumes to exclude
    excluded_volumes = [
      '/dev',                  # Device filesystem
      '/System/Volumes/VM',    # macOS VM volume
      '/System/Volumes/Preboot',
      '/System/Volumes/Update',
      '/System/Volumes/xarts',
      '/System/Volumes/iSCPreboot',
      '/System/Volumes/Hardware',
      '/private/var/vm',       # Virtual memory
      '/proc',                 # Linux proc filesystem
      '/sys',                  # Linux sys filesystem
      '/run',                  # Linux runtime data
      '/dev/shm'               # Linux shared memory
    ]

    # Define regex patterns for volumes to exclude
    excluded_patterns = [
      %r{^/Volumes/\.timemachine},  # Time Machine backups
      %r{^/private/var/folders},    # Temporary system folders
      %r{^/System/Volumes}          # System volumes
    ]

    if RUBY_PLATFORM =~ /darwin/
      # macOS
      df_output = `df -h`
      df_output.split("\n")[1..-1].each do |line|
        parts = line.split
        next if parts.size < 9
        filesystem = parts[0]
        size = parts[1]
        used = parts[2]
        available = parts[3]
        capacity = parts[4].gsub('%', '').to_i
        mount = parts[8]

        # Skip excluded volumes
        next if excluded_volumes.include?(mount)
        next if excluded_patterns.any? { |pattern| mount =~ pattern }

        # Skip special filesystems
        next if filesystem == 'devfs' || filesystem == 'map' || filesystem.start_with?('map ')

        disks[mount] = {
          filesystem: filesystem,
          size: size,
          used: used,
          available: available,
          capacity: capacity,
          status: capacity > 90 ? 'critical' : (capacity > 80 ? 'warning' : 'ok')
        }
      end
    elsif File.exist?('/proc/mounts')
      # Linux
      df_output = `df -h`
      df_output.split("\n")[1..-1].each do |line|
        parts = line.split
        next if parts.size < 6
        filesystem = parts[0]
        size = parts[1]
        used = parts[2]
        available = parts[3]
        capacity = parts[4].gsub('%', '').to_i
        mount = parts[5]

        # Skip excluded volumes
        next if excluded_volumes.include?(mount)
        next if excluded_patterns.any? { |pattern| mount =~ pattern }

        # Skip special filesystems
        next if filesystem == 'devfs' || filesystem == 'tmpfs' || filesystem == 'sysfs' ||
                filesystem == 'proc' || filesystem == 'devtmpfs' || filesystem == 'securityfs'

        disks[mount] = {
          filesystem: filesystem,
          size: size,
          used: used,
          available: available,
          capacity: capacity,
          status: capacity > 90 ? 'critical' : (capacity > 80 ? 'warning' : 'ok')
        }
      end
    end

    # Add application-specific directories
    app_dirs = {
      'log_dir' => Rails.root.join('log').to_s,
      'tmp_dir' => Rails.root.join('tmp').to_s,
      'public_dir' => Rails.root.join('public').to_s
    }

    app_dirs.each do |name, path|
      if Dir.exist?(path)
        size_bytes = directory_size(path)
        disks[name] = {
          path: path,
          size: format_size(size_bytes),
          status: size_bytes > 1.gigabyte ? 'warning' : 'ok'
        }
      end
    end

    {
      disks: disks,
      status: disks.values.any? { |d| d[:status] == 'critical' } ? 'critical' :
              (disks.values.any? { |d| d[:status] == 'warning' } ? 'warning' : 'ok')
    }
  rescue => e
    { error: e.message, status: 'unknown' }
  end

  def network_stats
    stats = {}

    # Get network interfaces
    if RUBY_PLATFORM =~ /darwin/
      # macOS
      interfaces = `ifconfig -a | grep -E '^[a-z]' | awk '{print $1}' | sed 's/://'`.split("\n")
      interfaces.each do |interface|
        next if interface =~ /lo\d*/  # Skip loopback
        ip_info = `ifconfig #{interface} | grep 'inet ' | awk '{print $2}'`.strip
        stats[interface] = {
          ip: ip_info,
          status: ip_info.empty? ? 'down' : 'up'
        }
      end
    elsif File.exist?('/proc/net/dev')
      # Linux
      File.readlines('/proc/net/dev').each do |line|
        next unless line =~ /^\s*(\w+):/
        interface = $1
        next if interface =~ /lo/  # Skip loopback
        ip_info = `ip addr show #{interface} | grep 'inet ' | awk '{print $2}' | cut -d/ -f1`.strip
        stats[interface] = {
          ip: ip_info,
          status: ip_info.empty? ? 'down' : 'up'
        }
      end
    end

    # Add external connectivity check
    begin
      external_check = Net::HTTP.get_response(URI('https://www.google.com')).code == '200'
      stats['external_connectivity'] = { status: external_check ? 'ok' : 'error' }
    rescue => e
      stats['external_connectivity'] = { status: 'error', error: e.message }
    end

    # Add DNS resolution check
    begin
      dns_check = Resolv.getaddress('www.google.com').present?
      stats['dns_resolution'] = { status: dns_check ? 'ok' : 'error' }
    rescue => e
      stats['dns_resolution'] = { status: 'error', error: e.message }
    end

    {
      interfaces: stats,
      status: (stats['external_connectivity'][:status] == 'ok' && stats['dns_resolution'][:status] == 'ok') ? 'ok' : 'error'
    }
  rescue => e
    { error: e.message, status: 'unknown' }
  end

  def request_statistics
    # This would ideally come from a monitoring system or log analysis
    # For demonstration, we'll create some sample data
    {
      last_hour: {
        total: 120 + rand(50),
        success_rate: 98.5 - rand(5.0),
        avg_response_time: 150 + rand(100),
        status_codes: {
          '200': 115 + rand(30),
          '404': 3 + rand(5),
          '500': 1 + rand(3)
        }
      },
      endpoints: {
        '/api/v1/courses': { avg_time: 120 + rand(50), count: 35 + rand(20) },
        '/api/v1/users': { avg_time: 90 + rand(40), count: 28 + rand(15) },
        '/health': { avg_time: 30 + rand(20), count: 15 + rand(10) }
      }
    }
  rescue => e
    { error: e.message }
  end

  def error_summary
    # In a real app, you would analyze log files or error tracking service
    log_file = Rails.root.join('log', "#{Rails.env}.log")
    recent_errors = []

    if File.exist?(log_file)
      begin
        # Get last 1000 lines and scan for errors
        log_tail = `tail -n 1000 #{log_file}`
        error_lines = log_tail.split("\n").select { |line| line.include?(' ERROR ') }

        # Group similar errors
        grouped_errors = {}
        error_lines.each do |line|
          # Extract timestamp and error message
          if line =~ /\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)\].*ERROR.*?(\w+Error|Exception):(.*?)$/
            timestamp, error_type, message = $1, $2, $3.strip
            key = "#{error_type}: #{message[0..100]}"
            grouped_errors[key] ||= { count: 0, last_seen: nil, type: error_type, message: message }
            grouped_errors[key][:count] += 1
            grouped_errors[key][:last_seen] = timestamp if grouped_errors[key][:last_seen].nil? || timestamp > grouped_errors[key][:last_seen]
          end
        end

        # Sort by count and take top 10
        recent_errors = grouped_errors.map { |k, v| v.merge(error: k) }
                                     .sort_by { |e| -e[:count] }
                                     .first(10)
      rescue => e
        recent_errors << { error: "Error analyzing logs: #{e.message}", count: 1, last_seen: Time.current.iso8601 }
      end
    end

    {
      count: recent_errors.sum { |e| e[:count] },
      recent: recent_errors,
      status: recent_errors.any? ? 'warning' : 'ok'
    }
  rescue => e
    { error: e.message, status: 'unknown' }
  end

  def dependency_status
    dependencies = {}

    # Check external services
    dependencies['email'] = check_email_service
    dependencies['storage'] = check_storage_service

    # Check gem dependencies
    dependencies['gems'] = {
      status: 'ok',
      outdated: outdated_gems
    }

    {
      services: dependencies,
      status: dependencies.values.any? { |d| d[:status] == 'error' } ? 'error' : 'ok'
    }
  rescue => e
    { error: e.message, status: 'unknown' }
  end

  def collect_issues
    issues = []

    # Database issues
    unless @health_data[:database][:connected]
      issues << { component: 'Database', severity: 'critical', message: 'Database connection failed', details: @health_data[:database][:error] }
    end

    if @health_data[:database][:connected] && @health_data[:database][:active_connections].to_f / @health_data[:database][:pool_size] > 0.8
      issues << { component: 'Database', severity: 'warning', message: 'Connection pool near capacity',
                 details: "#{@health_data[:database][:active_connections]}/#{@health_data[:database][:pool_size]} connections used" }
    end

    # Redis issues
    unless @health_data[:redis][:connected]
      issues << { component: 'Redis', severity: 'critical', message: 'Redis connection failed', details: @health_data[:redis][:error] }
    end

    # Job system issues
    if @health_data[:job_system][:status] != 'ok'
      severity = @health_data[:job_system][:status] == 'warning' ? 'warning' : 'critical'
      issues << { component: 'Background Jobs', severity: severity, message: 'Job system issues detected',
                 details: @health_data[:job_system][:error] || 'Workers or dispatcher not running' }
    end

    # Disk space issues
    @health_data[:disk][:disks].each do |mount, info|
      if info[:status] == 'critical'
        issues << { component: 'Disk Space', severity: 'critical', message: "#{mount} is critically low on space",
                   details: "#{info[:capacity]}% used (#{info[:used]}/#{info[:size]})" }
      elsif info[:status] == 'warning'
        issues << { component: 'Disk Space', severity: 'warning', message: "#{mount} is running low on space",
                   details: "#{info[:capacity]}% used (#{info[:used]}/#{info[:size]})" }
      end
    end

    # Network issues
    if @health_data[:network][:status] == 'error'
      issues << { component: 'Network', severity: 'critical', message: 'Network connectivity issues detected',
                 details: @health_data[:network][:error] || 'External connectivity or DNS resolution failed' }
    end

    # Error log issues
    if @health_data[:errors][:status] == 'warning' && @health_data[:errors][:count] > 0
      issues << { component: 'Application Errors', severity: 'warning', message: "#{@health_data[:errors][:count]} errors in recent logs",
                 details: "Most frequent: #{@health_data[:errors][:recent].first[:error]}" }
    end

    # Dependency issues
    @health_data[:dependencies][:services].each do |service, info|
      if info[:status] == 'error'
        issues << { component: "Dependency: #{service}", severity: 'critical', message: "#{service} service unavailable",
                   details: info[:error] || 'Connection failed' }
      end
    end

    # System load issues
    if @health_data[:system][:load_average][0] > 5.0  # Adjust threshold as needed
      issues << { component: 'System Load', severity: 'warning', message: 'High system load detected',
                 details: "Load average: #{@health_data[:system][:load_average].map { |l| '%.2f' % l }.join(' / ')}" }
    end

    issues
  end

  def generate_summary
    critical_count = @health_data[:issues].count { |i| i[:severity] == 'critical' }
    warning_count = @health_data[:issues].count { |i| i[:severity] == 'warning' }

    status = if critical_count > 0
               'critical'
             elsif warning_count > 0
               'warning'
             else
               'healthy'
             end

    components = {
      database: @health_data[:database][:connected] ? 'ok' : 'error',
      redis: @health_data[:redis][:connected] ? 'ok' : 'error',
      job_system: @health_data[:job_system][:status],
      disk: @health_data[:disk][:status],
      network: @health_data[:network][:status],
      errors: @health_data[:errors][:status],
      dependencies: @health_data[:dependencies][:status]
    }

    # Check PostgreSQL connections
    if @health_data[:job_system][:pg_connections] && @health_data[:job_system][:pg_connections][:warning]
      components[:database] = 'warning'
    end

    # Check disk space
    if @health_data[:job_system][:disk_space] && @health_data[:job_system][:disk_space][:warning]
      components[:disk] = 'warning'

      # If disk space is critically low (>95%), mark as error
      if @health_data[:job_system][:disk_space][:percentage] > 95
        components[:disk] = 'error'
      end
    end

    # Generate diagnostic details
    diagnostic_details = []

    # Add overall status message
    case status
    when 'critical'
      diagnostic_details << "CRITICAL: #{critical_count} critical issues require immediate attention"
    when 'warning'
      diagnostic_details << "WARNING: #{warning_count} warnings should be addressed soon"
    else
      diagnostic_details << "All systems are operational"
    end

    # Add specific component details
    if components[:database] != 'ok'
      diagnostic_details << "Database: #{components[:database].upcase} - #{database_diagnostic_message}"
    end

    if components[:redis] != 'ok'
      diagnostic_details << "Redis: #{components[:redis].upcase} - #{redis_diagnostic_message}"
    end

    if components[:job_system] != 'ok'
      diagnostic_details << "Job System: #{components[:job_system].upcase} - #{job_system_diagnostic_message}"
    end

    if components[:disk] != 'ok'
      diagnostic_details << "Disk Space: #{components[:disk].upcase} - #{disk_diagnostic_message}"
    end

    if components[:network] != 'ok'
      diagnostic_details << "Network: #{components[:network].upcase} - #{network_diagnostic_message}"
    end

    # Add specific issues from the issues list
    @health_data[:issues].each do |issue|
      next if diagnostic_details.any? { |detail| detail.include?(issue[:message]) }
      diagnostic_details << "#{issue[:component]}: #{issue[:severity].upcase} - #{issue[:message]}"
    end

    {
      status: status,
      message: case status
               when 'critical' then "#{critical_count} critical issues require immediate attention"
               when 'warning' then "#{warning_count} warnings should be addressed soon"
               else "All systems operational"
               end,
      components: components,
      critical_count: critical_count,
      warning_count: warning_count,
      diagnostic_details: diagnostic_details
    }
  end

  # Helper methods for diagnostic messages
  def database_diagnostic_message
    if !@health_data[:database][:connected]
      "Database connection failed: #{@health_data[:database][:error]}"
    elsif @health_data[:database][:connection_percentage] > 80
      "Connection pool near capacity (#{@health_data[:database][:connection_percentage]}%)"
    else
      "Database issues detected"
    end
  end

  def redis_diagnostic_message
    if !@health_data[:redis][:connected]
      "Redis connection failed: #{@health_data[:redis][:error]}"
    else
      "Redis issues detected"
    end
  end

  def job_system_diagnostic_message
    if @health_data[:job_system][:error]
      "#{@health_data[:job_system][:error]}"
    elsif !@health_data[:job_system][:dispatcher_running]
      "Job dispatcher not running"
    elsif @health_data[:job_system][:active_workers] == 0
      "No active job workers"
    else
      "Job system issues detected"
    end
  end

  def disk_diagnostic_message
    if @health_data[:disk][:disks].any? { |_, info| info[:status] == 'critical' }
      critical_disk = @health_data[:disk][:disks].find { |_, info| info[:status] == 'critical' }
      "#{critical_disk[0]} is critically low on space (#{critical_disk[1][:capacity]}% used)"
    elsif @health_data[:job_system][:disk_space] && @health_data[:job_system][:disk_space][:warning]
      "Disk space is running low (#{@health_data[:job_system][:disk_space][:percentage]}% used)"
    else
      "Disk space issues detected"
    end
  end

  def network_diagnostic_message
    if @health_data[:network][:interfaces]['external_connectivity'] &&
       @health_data[:network][:interfaces]['external_connectivity'][:status] != 'ok'
      "External connectivity issues detected"
    elsif @health_data[:network][:interfaces]['dns_resolution'] &&
          @health_data[:network][:interfaces]['dns_resolution'][:status] != 'ok'
      "DNS resolution issues detected"
    else
      "Network connectivity issues detected"
    end
  end

  def cpu_usage
    if File.exist?('/proc/stat')
      # Linux
      stat1 = File.readlines('/proc/stat').first.split
      sleep 0.1
      stat2 = File.readlines('/proc/stat').first.split

      # Extract CPU times
      cpu1 = stat1[1..4].map(&:to_i).sum
      idle1 = stat1[4].to_i
      cpu2 = stat2[1..4].map(&:to_i).sum
      idle2 = stat2[4].to_i

      # Calculate usage
      cpu_diff = cpu2 - cpu1
      idle_diff = idle2 - idle1

      usage = cpu_diff > 0 ? ((1 - idle_diff.to_f / cpu_diff) * 100).round(1) : 0
    elsif RUBY_PLATFORM =~ /darwin/
      # macOS
      usage = `top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//'`.to_f
    else
      usage = nil
    end

    usage || 0
  rescue
    0
  end

  def count_open_files
    if File.directory?("/proc/#{Process.pid}/fd")
      Dir.entries("/proc/#{Process.pid}/fd").size - 2  # Subtract . and ..
    else
      `lsof -p #{Process.pid} | wc -l`.to_i - 1  # Subtract header
    end
  rescue
    0
  end

  def filtered_env_vars
    # Return a subset of environment variables, filtering out sensitive ones
    safe_vars = %w[RAILS_ENV RACK_ENV PATH PWD USER HOME LANG TZ]
    safe_vars.each_with_object({}) do |var, hash|
      hash[var] = ENV[var] if ENV[var]
    end
  end

  def top_loaded_gems
    # Return top 10 loaded gems with their versions
    Gem.loaded_specs.sort_by { |name, spec| name }.first(10).map do |name, spec|
      { name: name, version: spec.version.to_s }
    end
  end

  def directory_size(path)
    total_size = 0
    Find.find(path) do |f|
      total_size += File.size(f) if File.file?(f)
    end
    total_size
  rescue
    0
  end

  def format_size(size_bytes)
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    unit_index = 0
    size = size_bytes.to_f

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    "#{size.round(2)} #{units[unit_index]}"
  end

  def check_email_service
    # In a real app, you would check SMTP connection
    begin
      # Simulate a check
      smtp_configured = ENV['SMTP_ADDRESS'].present? && ENV['SMTP_PORT'].present?
      { status: smtp_configured ? 'ok' : 'warning', message: smtp_configured ? 'Configured' : 'Not configured' }
    rescue => e
      { status: 'error', error: e.message }
    end
  end

  def check_storage_service
    # In a real app, you would check S3/cloud storage
    begin
      storage_configured = ActiveStorage::Blob.service.present?
      { status: storage_configured ? 'ok' : 'warning', message: 'Active Storage available' }
    rescue => e
      { status: 'error', error: e.message }
    end
  end

  def outdated_gems
    # In a real app, you might use Bundler::CLI.outdated
    # For demo purposes, we'll return a sample
    [
      { name: 'rails', current: Rails::VERSION::STRING, latest: '7.1.0' },
      { name: 'puma', current: '6.0.0', latest: '6.3.0' }
    ]
  rescue => e
    [{ name: 'Error checking gems', error: e.message }]
  end

  def process_status
    recent = Time.current - SolidQueue.stale_process_threshold
    processes = SolidQueue::Process.where("last_heartbeat_at > ?", recent)

    {
      workers: processes.where(kind: "Worker").count,
      dispatchers: processes.where(kind: "Dispatcher").count,
      details: processes.map { |p| process_details(p) }
    }
  end

  def process_details(process)
    {
      id: process.id,
      kind: process.kind,
      name: process.name,
      hostname: process.hostname,
      pid: process.pid,
      last_heartbeat: process.last_heartbeat_at,
      metadata: process.metadata
    }
  end

  def queue_metrics
    queues = {}
    SolidQueue::ReadyExecution.group(:queue_name).count.each do |queue, count|
      queues[queue] = {
        ready: count,
        scheduled: SolidQueue::ScheduledExecution.where(queue_name: queue).count,
        failed: SolidQueue::Job.where(queue_name: queue).where.not(failed_at: nil).count
      }
    end
    queues
  end

  def job_stats
    {
      processed_last_hour: SolidQueue::Job.where("finished_at > ?", 1.hour.ago).count,
      failed_last_hour: SolidQueue::Job.where("failed_at > ?", 1.hour.ago).count,
      scheduled: SolidQueue::ScheduledExecution.count,
      ready: SolidQueue::ReadyExecution.count,
      recurring: SolidQueue::RecurringExecution.count
    }
  end
end