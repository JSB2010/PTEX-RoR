Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.keep_original_rails_log = true
  config.lograge.logger = ActiveSupport::Logger.new "#{Rails.root}/log/lograge_#{Rails.env}.log"
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.ignore_actions = [
    'HealthController#show',
    'ActiveStorage::DiskController#show',
    'ActiveStorage::BlobsController#show',
    'Rack::MiniProfiler#call'
  ]

  # Add custom fields to the log output
  config.lograge.custom_options = lambda do |event|
    exceptions = %w[controller action format id utf8 authenticity_token]
    params = event.payload[:params].except(*exceptions)
    
    # Ensure sensitive parameters are filtered
    params = filter_sensitive_params(params)

    {
      # Request details
      params: params,
      time: Time.current.iso8601(6), # Include microseconds
      request_id: event.payload[:request_id],
      correlation_id: event.payload[:correlation_id] || SecureRandom.uuid,
      session_id: event.payload[:session_id],
      
      # User context
      user_id: event.payload[:user_id],
      remote_ip: anonymize_ip(event.payload[:remote_ip]),
      user_agent: event.payload[:user_agent],
      request_origin: event.payload[:headers]&.[]('Origin'),
      request_referer: event.payload[:headers]&.[]('Referer'),
      
      # Performance metrics
      db_runtime: event.payload[:db_runtime],
      view_runtime: event.payload[:view_runtime],
      memory_usage: get_memory_usage,
      cpu_usage: get_cpu_usage,
      
      # Database metrics
      db_query_count: event.payload[:db_query_count],
      db_cached_count: event.payload[:db_cached_count],
      
      # Cache metrics
      cache_hits: event.payload[:cache_hits],
      cache_misses: event.payload[:cache_misses],
      cache_utilization: get_cache_stats,
      
      # Error details
      exception: event.payload[:exception]&.first,
      exception_message: event.payload[:exception]&.last,
      exception_backtrace: event.payload[:exception_object]&.backtrace&.first(5),
      
      # Application context
      environment: Rails.env,
      git_sha: ENV['GIT_SHA'],
      server_hostname: Socket.gethostname,
      process_id: Process.pid,
      
      # Resource utilization
      gc_stats: collect_gc_stats,
      thread_stats: collect_thread_stats,
      
      # Request security context
      request_auth_type: event.payload[:headers]&.[]('Authorization')&.split(' ')&.first,
      request_tls_version: event.payload[:headers]&.[]('SSL_PROTOCOL'),
      request_cipher: event.payload[:headers]&.[]('SSL_CIPHER')
    }.compact
  end

  # Configure development logging
  if Rails.env.development?
    config.lograge.keep_original_rails_log = true
    config.lograge.formatter = Lograge::Formatters::KeyValue.new
  end

  # Add custom status code mapping
  config.lograge.custom_status = lambda do |event|
    case event.payload[:status]
    when 404 then 'not_found'
    when 401 then 'unauthorized'
    when 403 then 'forbidden'
    when 422 then 'unprocessable_entity'
    when 429 then 'rate_limited'
    when 500..599 then 'server_error'
    else event.payload[:status]
    end
  end

  # Add request-specific context
  config.lograge.custom_payload do |controller|
    user = controller.try(:current_user)
    user_id = if user.is_a?(Array)
      user.first&.first # Extract ID from Warden session array if that's what we got
    elsif user.respond_to?(:id)
      user.id
    end
    
    {
      user_id: user_id,
      ip: controller.request.remote_ip,
      url: controller.request.url,
      method: controller.request.request_method
    }
  end

  # Subscribe to custom events for logging
  ActiveSupport::Notifications.subscribe('rack_attack.blocked') do |name, start, finish, id, payload|
    Rails.logger.warn(
      security_event: {
        type: 'rack_attack.blocked',
        remote_ip: anonymize_ip(payload[:request].ip),
        path: payload[:request].path,
        matched_rule: payload[:rule_type],
        duration: finish - start
      }.to_json
    )
  end

  # Subscribe to cache events
  ActiveSupport::Notifications.subscribe('cache_operation.active_support') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    Rails.logger.debug(
      cache_event: {
        operation: event.payload[:operation],
        key: event.payload[:key],
        hit: event.payload[:hit],
        duration: event.duration
      }.to_json
    )
  end

  # Subscribe to job execution events
  ActiveSupport::Notifications.subscribe('perform.active_job') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    job = event.payload[:job]
    Rails.logger.info(
      job_event: {
        job_id: job.job_id,
        job_class: job.class.name,
        queue_name: job.queue_name,
        duration: event.duration,
        arguments: job.arguments,
        executions: job.executions
      }.to_json
    )
  end
end

private

def filter_sensitive_params(params)
  params.deep_transform_values do |value|
    if value.is_a?(String) && sensitive_param?(value)
      '[FILTERED]'
    else
      value
    end
  end
end

def sensitive_param?(value)
  patterns = [
    /password/i,
    /token/i,
    /secret/i,
    /key/i,
    /authorization/i,
    /session/i
  ]
  
  patterns.any? { |pattern| value.to_s.match?(pattern) }
end

def filter_headers(headers)
  filtered = headers.to_h.dup
  
  # Remove sensitive headers
  %w[
    Cookie
    Authorization
    X-CSRF-Token
    Session
    X-API-Key
  ].each { |header| filtered.delete(header) }
  
  filtered
end

def anonymize_ip(ip)
  return nil if ip.nil?
  
  # Anonymize the last octet for IPv4 or last 80 bits for IPv6
  ip_addr = IPAddr.new(ip)
  if ip_addr.ipv4?
    ip_addr.mask(24).to_s
  else
    ip_addr.mask(48).to_s
  end
rescue IPAddr::InvalidAddressError
  ip
end

def get_memory_usage
  {
    rss: `ps -o rss= -p #{Process.pid}`.to_i / 1024, # MB
    vmsize: `ps -o vsz= -p #{Process.pid}`.to_i / 1024, # MB
    heap_slots: GC.stat[:heap_live_slots]
  }
end

def get_cpu_usage
  times = Process.times
  {
    user: times.utime,
    system: times.stime,
    total: times.utime + times.stime,
    child_user: times.cutime,
    child_system: times.cstime
  }
end

def get_cache_stats
  return {} unless Rails.cache.respond_to?(:stats)
  
  stats = Rails.cache.stats
  {
    hits: stats[:hits],
    misses: stats[:misses],
    hit_rate: stats[:hits].to_f / (stats[:hits] + stats[:misses])
  }
rescue => e
  Rails.logger.error("Failed to collect cache stats: #{e.message}")
  {}
end

def collect_gc_stats
  {
    count: GC.stat[:count],
    heap_allocated: GC.stat[:heap_allocated_pages],
    heap_sorted: GC.stat[:heap_sorted_length],
    heap_allocatable: GC.stat[:heap_allocatable_pages],
    heap_available: GC.stat[:heap_available_slots],
    heap_live: GC.stat[:heap_live_slots],
    heap_free: GC.stat[:heap_free_slots],
    total_allocated: GC.stat[:total_allocated_pages],
    total_freed: GC.stat[:total_freed_pages]
  }
end

def collect_thread_stats
  {
    count: Thread.list.count,
    status: Thread.list.group_by(&:status).transform_values(&:count),
    queue_size: Thread.pending_interrupt_queue_length
  }
end