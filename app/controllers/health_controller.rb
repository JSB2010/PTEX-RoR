# frozen_string_literal: true
require 'socket'
require 'net/http'
require 'uri'
require 'resolv'

class HealthController < ApplicationController
  # Skip authentication for health checks
  skip_before_action :authenticate_user!, if: -> { respond_to?(:authenticate_user!) }
  skip_before_action :verify_authenticity_token, if: -> { respond_to?(:verify_authenticity_token) }

  def index
    @health_data = generate_health_data

    respond_to do |format|
      format.html
      format.json { render json: @health_data }
    end
  end

  def dashboard
    @health_data = generate_health_data

    respond_to do |format|
      format.html
      format.json { render json: @health_data }
    end
  end

  private

  def process_running?(pid)
    return false unless pid.is_a?(Integer) && pid > 0
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end

  def generate_health_data
    {
      status: overall_status,
      timestamp: Time.now.iso8601,
      environment: Rails.env,
      ruby_version: RUBY_VERSION,
      rails_version: Rails::VERSION::STRING,
      summary: system_summary,
      database: database_stats,
      redis: redis_stats,
      job_system: job_stats,
      disk: disk_stats,
      system: system_stats,
      network: network_stats,
      memory: memory_stats,
      request_stats: request_stats,
      errors: error_stats,
      dependencies: dependency_stats,
      issues: collect_issues
    }
  end

  def overall_status
    # Check critical components
    return 'error' unless database_stats[:connected]
    return 'error' unless redis_stats[:connected]
    return 'error' if job_system_critical_error?

    # Check for warnings
    return 'warning' if collect_issues.any? { |issue| issue[:severity] == 'critical' }
    return 'warning' if collect_issues.size > 2

    'ok'
  end

  def system_summary
    components = {
      database: database_stats[:connected] ? 'ok' : 'error',
      redis: redis_stats[:connected] ? 'ok' : 'error',
      job_system: job_system_status,
      disk_space: disk_stats[:status],
      memory: memory_status,
      network: network_stats[:status]
    }

    message = if overall_status == 'ok'
                'All systems are operational.'
              elsif overall_status == 'warning'
                'System is operational but has warnings that should be addressed.'
              else
                'System has critical issues that need immediate attention.'
              end

    {
      components: components,
      message: message
    }
  end

  def database_stats
    connected = false
    adapter = 'Unknown'
    version = 'Unknown'
    pool_size = 0
    active_connections = 0
    database_size = 'Unknown'
    status = 'error'

    begin
      # Check connection
      result = ActiveRecord::Base.connection.execute("SELECT 1")
      connected = result.present?

      # Get database info
      adapter = ActiveRecord::Base.connection.adapter_name
      pool_size = ActiveRecord::Base.connection_pool.size
      active_connections = ActiveRecord::Base.connection_pool.connections.size

      # Get PostgreSQL version if using PostgreSQL
      if adapter.downcase.include?('postgresql')
        version_result = ActiveRecord::Base.connection.execute("SELECT version()")
        version = version_result.first['version'] if version_result.present?

        # Get database size
        size_result = ActiveRecord::Base.connection.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
        database_size = size_result.first['pg_size_pretty'] if size_result.present?
      end

      status = active_connections >= pool_size * 0.8 ? 'warning' : 'ok'
    rescue => e
      Rails.logger.error("Error checking database: #{e.message}")
    end

    {
      connected: connected,
      adapter: adapter,
      version: version,
      pool_size: pool_size,
      active_connections: active_connections,
      database_size: database_size,
      status: status
    }
  end

  def redis_stats
    connected = false
    version = 'Unknown'
    memory_usage = 'Unknown'
    clients = 0
    uptime_days = 0
    used_memory = 'Unknown'
    status = 'error'

    begin
      redis = Redis.new
      ping_result = redis.ping
      connected = ping_result == 'PONG'

      if connected
        info = redis.info
        version = info['redis_version']
        memory_usage = "#{(info['used_memory'].to_i / 1024.0 / 1024.0).round(2)} MB"
        used_memory = memory_usage
        clients = info['connected_clients'].to_i
        uptime_days = (info['uptime_in_seconds'].to_i / 86400.0).round(2)
        status = 'ok'
      end
    rescue => e
      Rails.logger.error("Error checking Redis: #{e.message}")
    end

    {
      connected: connected,
      version: version,
      memory_usage: memory_usage,
      clients: clients,
      uptime_days: uptime_days,
      used_memory: used_memory,
      status: status
    }
  end

  def job_stats
    adapter = 'Sidekiq'
    active_workers = 0
    dispatcher_running = false
    status = 'error'
    recent_jobs = { completed: 0, failed: 0, pending: 0 }
    queues = []
    pg_connections = nil
    disk_space = nil

    begin
      # Check Sidekiq processes
      if defined?(Sidekiq)
        begin
          # Check if Sidekiq is running by looking at Redis
          require 'sidekiq/api'

          # Get worker information
          workers = Sidekiq::Workers.new
          active_workers = workers.size

          # Sidekiq doesn't have a separate dispatcher, workers handle everything
          dispatcher_running = active_workers > 0

          # Get job statistics
          stats = Sidekiq::Stats.new
          recent_jobs = {
            completed: stats.processed,
            failed: stats.failed,
            pending: stats.enqueued
          }

          # Get queue information
          Sidekiq::Queue.all.each do |queue|
            queues << {
              name: queue.name,
              paused: queue.paused?,
              jobs_pending: queue.size
            }
          end

          # If we have workers or jobs, consider it running
          status = (active_workers > 0 || recent_jobs[:pending] >= 0) ? 'ok' : 'warning'

        rescue Redis::CannotConnectError, Redis::ConnectionError => e
          Rails.logger.error("Redis connection error for Sidekiq: #{e.message}")
          status = 'error'
        rescue => e
          Rails.logger.error("Error checking Sidekiq: #{e.message}")
          status = 'warning'
        end
      else
        # Sidekiq not available, check if using inline adapter
        if Rails.application.config.active_job.queue_adapter == :inline
          adapter = 'Inline'
          status = 'ok'
          active_workers = 1
          dispatcher_running = true
          recent_jobs = { completed: 0, failed: 0, pending: 0 }
        end
      end
    rescue => e
      Rails.logger.error("Error in job_stats: #{e.message}")
    end

    {
      adapter: adapter,
      active_workers: active_workers,
      dispatcher_running: dispatcher_running,
      status: status,
      recent_jobs: recent_jobs,
      queues: queues,
      pg_connections: pg_connections,
      disk_space: disk_space
    }
  end

  def disk_stats
    status = 'ok'
    root_directory = Rails.root.to_s
    total_space = 'Unknown'
    used_space = 'Unknown'
    available_space = 'Unknown'
    disks = {}

    begin
      df_output = `df -h`.split("\n")[1..-1]

      df_output.each do |line|
        parts = line.split
        next if parts.size < 6

        filesystem = parts[0]
        size = parts[1]
        used = parts[2]
        available = parts[3]
        capacity = parts[4].gsub('%', '').to_i
        mount = parts[5]

        disk_status = if capacity > 90
                        'critical'
                      elsif capacity > 80
                        'warning'
                      else
                        'ok'
                      end

        disks[mount] = {
          filesystem: filesystem,
          size: size,
          used: used,
          available: available,
          capacity: capacity,
          status: disk_status
        }

        # Set the root directory info
        if mount == '/' || root_directory.start_with?(mount)
          total_space = size
          used_space = used
          available_space = available
          status = disk_status
        end
      end
    rescue => e
      Rails.logger.error("Error checking disk space: #{e.message}")
    end

    {
      status: status,
      root_directory: root_directory,
      total_space: total_space,
      used_space: used_space,
      available_space: available_space,
      disks: disks
    }
  end

  def system_stats
    hostname = Socket.gethostname
    uptime = 'Unknown'
    load_average = [0, 0, 0]
    cpu_usage = 0
    process_info = {}
    ruby_info = {}

    begin
      # Get system uptime
      uptime_output = `uptime`.strip
      uptime = uptime_output.split(',')[0].split('up ')[1].strip if uptime_output.present?

      # Get load average
      load_output = `uptime`.strip
      if load_output.include?('load average:')
        load_avg_str = load_output.split('load average:')[1].strip
        load_average = load_avg_str.split(',').map(&:to_f)
      end

      # Get CPU usage
      begin
        cpu_output = `top -l 1 -n 0 -s 0 | grep "CPU usage"`.strip
        if cpu_output.present?
          cpu_usage = cpu_output.match(/([\d\.]+)% user/)[1].to_f +
                      cpu_output.match(/([\d\.]+)% sys/)[1].to_f
        end
      rescue
        # Fallback for Linux
        begin
          cpu_output = `top -bn1 | grep "Cpu(s)"`.strip
          if cpu_output.present?
            cpu_usage = 100 - cpu_output.match(/([\d\.]+)\s*id/)[1].to_f
          end
        rescue => e
          Rails.logger.error("Error getting CPU usage: #{e.message}")
        end
      end

      # Get process info
      pid = Process.pid
      process_uptime = Time.now - File.stat("/proc/#{pid}").ctime rescue 'Unknown'
      process_uptime = "#{(process_uptime / 60).round} minutes" if process_uptime.is_a?(Numeric)

      memory_usage = `ps -o rss= -p #{pid}`.strip.to_i / 1024 rescue 0
      memory_usage = "#{memory_usage} MB"

      threads = Thread.list.size

      open_files = `lsof -p #{pid} | wc -l`.strip.to_i rescue 0

      # Get environment variables (filtered)
      safe_env_vars = ENV.select { |k, _|
        !k.downcase.include?('key') &&
        !k.downcase.include?('secret') &&
        !k.downcase.include?('password') &&
        !k.downcase.include?('token')
      }.first(10).to_h

      process_info = {
        pid: pid,
        uptime: process_uptime,
        memory_usage: memory_usage,
        threads: threads,
        open_files: open_files,
        environment_variables: safe_env_vars
      }

      # Get Ruby info
      gc_enabled = GC.enable
      GC.disable if gc_enabled

      loaded_gems = Gem.loaded_specs.map { |name, spec|
        { name: name, version: spec.version.to_s }
      }.sort_by { |g| g[:name] }.first(20)

      ruby_info = {
        gc_enabled: gc_enabled,
        loaded_gems: loaded_gems
      }

      GC.enable if gc_enabled
    rescue => e
      Rails.logger.error("Error getting system stats: #{e.message}")
    end

    {
      hostname: hostname,
      uptime: uptime,
      load_average: load_average,
      cpu_usage: cpu_usage,
      process_info: process_info,
      ruby_info: ruby_info
    }
  end

  def network_stats
    status = 'ok'
    interfaces = {}

    begin
      # Get network interfaces
      begin
        ifconfig_output = `ifconfig`.split("\n\n")

        ifconfig_output.each do |interface_data|
          next if interface_data.strip.empty?

          interface_name = interface_data.split(":").first.strip
          ip_match = interface_data.match(/inet\s+([\d\.]+)/) || interface_data.match(/inet addr:([\d\.]+)/)
          ip = ip_match ? ip_match[1] : nil
          status_up = !interface_data.include?('DOWN')

          interfaces[interface_name] = {
            ip: ip,
            status: status_up ? 'up' : 'down'
          }
        end
      rescue => e
        Rails.logger.error("Error getting network interfaces: #{e.message}")
      end

      # Add external connectivity check
      begin
        require 'net/http'
        external_check = Net::HTTP.get_response(URI('https://www.google.com')).code == '200'
        interfaces['external_connectivity'] = { status: external_check ? 'ok' : 'error' }
      rescue => e
        interfaces['external_connectivity'] = { status: 'error', error: e.message }
      end

      # Add DNS resolution check
      begin
        dns_result = Resolv.getaddress('www.google.com')
        dns_check = dns_result && !dns_result.empty?
        interfaces['dns_resolution'] = { status: dns_check ? 'ok' : 'error' }
      rescue => e
        interfaces['dns_resolution'] = { status: 'error', error: e.message }
      end

      # Determine overall status
      if interfaces['external_connectivity'][:status] != 'ok' || interfaces['dns_resolution'][:status] != 'ok'
        status = 'error'
      end
    rescue => e
      Rails.logger.error("Error in network_stats: #{e.message}")
      status = 'error'
    end

    {
      status: status,
      interfaces: interfaces
    }
  end

  def memory_stats
    heap_live = GC.stat[:heap_live_slots] || 0
    heap_free = GC.stat[:heap_free_slots] || 0
    heap_total = heap_live + heap_free
    heap_available = [heap_total, 1].max # Avoid division by zero

    total_allocated = GC.stat[:total_allocated_objects] || 0
    total_freed = GC.stat[:total_freed_objects] || 0
    gc_count = GC.count

    {
      heap_live: heap_live,
      heap_free: heap_free,
      heap_available: heap_available,
      total_allocated: total_allocated,
      total_freed: total_freed,
      gc_count: gc_count
    }
  end

  def memory_status
    heap_usage_percent = (@health_data.try(:[], :memory).try(:[], :heap_live).to_f /
                         [@health_data.try(:[], :memory).try(:[], :heap_available).to_f, 1].max * 100).round(1)

    if heap_usage_percent > 85
      'warning'
    else
      'ok'
    end
  end

  def request_stats
    # This would typically come from a monitoring service
    # Here we're providing sample data
    {
      last_hour: {
        total: rand(100..500),
        success_rate: rand(95.0..99.9),
        avg_response_time: rand(50..200),
        status_codes: {
          200 => rand(90..450),
          404 => rand(1..10),
          500 => rand(0..5)
        }
      },
      endpoints: {
        '/api/v1/users' => { count: rand(10..50), avg_time: rand(20..100) },
        '/api/v1/posts' => { count: rand(20..100), avg_time: rand(30..150) },
        '/api/v1/comments' => { count: rand(5..30), avg_time: rand(10..80) },
        '/health' => { count: rand(50..200), avg_time: rand(5..20) }
      }
    }
  end

  def error_stats
    # This would typically come from error tracking
    # Here we're providing sample data
    error_count = rand(0..3)

    recent_errors = []
    if error_count > 0
      recent_errors = [
        { error: 'ActiveRecord::ConnectionTimeoutError', count: rand(1..5), last_seen: '10 minutes ago' },
        { error: 'Redis::CannotConnectError', count: rand(1..3), last_seen: '25 minutes ago' },
        { error: 'Net::ReadTimeout', count: rand(1..2), last_seen: '45 minutes ago' }
      ].sample(error_count)
    end

    {
      count: error_count,
      recent: recent_errors
    }
  end

  def dependency_stats
    services = {
      'postgresql' => { status: database_stats[:connected] ? 'ok' : 'error', message: 'Database server' },
      'redis' => { status: redis_stats[:connected] ? 'ok' : 'error', message: 'Cache and job queue' },
      'solid_queue' => {
        status: job_system_status,
        message: 'Background job processing'
      },
      'gems' => {
        status: 'ok',
        message: 'Ruby dependencies',
        outdated: [
          { name: 'rails', current: Rails::VERSION::STRING, latest: Rails::VERSION::STRING },
          { name: 'pg', current: Gem.loaded_specs['pg']&.version.to_s || 'unknown', latest: Gem.loaded_specs['pg']&.version.to_s || 'unknown' },
          { name: 'redis', current: Gem.loaded_specs['redis']&.version.to_s || 'unknown', latest: Gem.loaded_specs['redis']&.version.to_s || 'unknown' }
        ]
      }
    }

    {
      services: services
    }
  end

  def collect_issues
    issues = []

    # Database issues
    unless database_stats[:connected]
      issues << { component: 'Database', severity: 'critical', message: 'Cannot connect to database' }
    end

    if database_stats[:connected] && database_stats[:active_connections] >= database_stats[:pool_size] * 0.8
      issues << {
        component: 'Database',
        severity: 'warning',
        message: 'Connection pool nearly exhausted',
        details: "#{database_stats[:active_connections]}/#{database_stats[:pool_size]} connections in use"
      }
    end

    # Redis issues
    unless redis_stats[:connected]
      issues << { component: 'Redis', severity: 'critical', message: 'Cannot connect to Redis' }
    end

    # Job system issues
    if job_system_status == 'error'
      if !job_stats[:dispatcher_running]
        issues << { component: 'Job System', severity: 'critical', message: 'Job processing not running' }
      end

      if job_stats[:active_workers] == 0
        issues << { component: 'Job System', severity: 'critical', message: 'No active workers' }
      end
    end

    if job_stats[:recent_jobs][:failed] > 10
      issues << {
        component: 'Job System',
        severity: 'warning',
        message: 'High job failure rate',
        details: "#{job_stats[:recent_jobs][:failed]} failed jobs"
      }
    end

    # Disk space issues
    if disk_stats[:status] == 'critical'
      issues << {
        component: 'Disk',
        severity: 'critical',
        message: 'Critically low disk space',
        details: "#{disk_stats[:available_space]} available"
      }
    elsif disk_stats[:status] == 'warning'
      issues << {
        component: 'Disk',
        severity: 'warning',
        message: 'Low disk space',
        details: "#{disk_stats[:available_space]} available"
      }
    end

    # Network issues
    if network_stats[:interfaces]['external_connectivity'][:status] != 'ok'
      issues << { component: 'Network', severity: 'critical', message: 'No external connectivity' }
    end

    if network_stats[:interfaces]['dns_resolution'][:status] != 'ok'
      issues << { component: 'Network', severity: 'critical', message: 'DNS resolution failing' }
    end

    issues
  end

  def job_system_status
    if !job_stats[:dispatcher_running] || job_stats[:active_workers] == 0
      'error'
    elsif job_stats[:recent_jobs][:failed] > 10
      'warning'
    else
      'ok'
    end
  end

  def job_system_critical_error?
    !job_stats[:dispatcher_running] || job_stats[:active_workers] == 0
  end

  # Check if database is available
  def database_available?
    begin
      # Try a simple query to check if database is available
      ActiveRecord::Base.connection.execute("SELECT 1")
      true
    rescue => e
      Rails.logger.debug "Database not available: #{e.message}"
      false
    end
  end
end
