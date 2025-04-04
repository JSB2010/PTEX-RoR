if defined?(Sentry)
  Sentry.init do |config|
    # Basic configuration
    config.dsn = ENV['SENTRY_DSN']
    config.environment = Rails.env
    config.release = ENV.fetch('GIT_SHA') { `git rev-parse HEAD`.strip }
    config.enabled_environments = %w[production staging]
    
    # Performance monitoring settings
    config.traces_sample_rate = ENV.fetch('SENTRY_TRACES_SAMPLE_RATE', 0.1).to_f
    config.profiles_sample_rate = ENV.fetch('SENTRY_PROFILES_SAMPLE_RATE', 0.1).to_f
    config.enable_tracing = true
    
    # Enable breadcrumbs for better debugging
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    
    # Configure send defaults
    config.send_default_pii = false
    config.include_local_variables = true
    
    # Set transport options
    config.transport.timeout = 5
    config.transport.ssl_verification = true
    config.transport.proxy = ENV['HTTP_PROXY'] if ENV['HTTP_PROXY']
    
    # Configure before_send to filter sensitive data
    config.before_send = lambda do |event, hint|
      # Skip errors from bots/crawlers
      return nil if hint[:request]&.user_agent =~ /bot|crawl|spider/i
      
      # Filter sensitive data
      if event.request
        event.request.cookies.clear
        event.request.headers.delete('Authorization')
        event.request.headers.delete('Cookie')
        event.request.headers.delete('X-CSRF-Token')
        
        # Filter sensitive params
        if event.request.data
          filtered_data = event.request.data.dup
          %w[password password_confirmation token access_token refresh_token].each do |key|
            filtered_data.gsub!(/(#{key}=)[^&]+/, '\1[FILTERED]')
          end
          event.request.data = filtered_data
        end
      end

      if event.transaction
        # Add memory stats
        if stats = MemoryMonitoring.memory_stats
          event.contexts[:memory] = {
            usage_mb: stats[:memory_usage_mb],
            gc_count: stats[:gc_stats][:count],
            heap_slots: stats[:gc_stats][:heap_live_slots]
          }
        end

        # Add database stats if available
        if defined?(ActiveRecord::Base)
          pool = ActiveRecord::Base.connection_pool
          event.contexts[:database] = {
            pool_size: pool.size,
            active_connections: pool.connections.count(&:in_use?),
            waiting_in_queue: pool.num_waiting_in_queue
          }
        end

        # Add Redis stats if available
        if defined?(Redis) && (redis = Redis.current)
          event.contexts[:redis] = {
            connected_clients: redis.info('clients')['connected_clients'],
            used_memory: redis.info('memory')['used_memory_human'],
            peak_memory: redis.info('memory')['used_memory_peak_human']
          }
        end
      end
      
      event
    end
    
    # Configure before_breadcrumb to filter sensitive data from breadcrumbs
    config.before_breadcrumb = lambda do |breadcrumb, hint|
      # Skip asset requests
      return nil if breadcrumb.category == 'http' && breadcrumb.data[:url] =~ /\.(js|css|png|jpg|gif|ico|woff|ttf)$/
      
      # Filter sensitive data from breadcrumbs
      if breadcrumb.category == 'http'
        breadcrumb.data.delete(:cookies)
        breadcrumb.data.delete(:authorization)
      end
      
      breadcrumb
    end
    
    # Set context defaults
    config.before_job = lambda do |job|
      Sentry.set_context('job', {
        job_class: job.class.name,
        job_id: job.job_id,
        queue_name: job.queue_name,
        arguments: job.arguments,
        executions: job.executions
      })
    end
    
    # Add Rails-specific context
    config.rails.report_rescued_exceptions = true
    config.rails.skippable_job_adapters = ['ActiveJob::QueueAdapters::SolidQueueAdapter']
    
    # Add custom tags
    config.tags = {
      server_name: Socket.gethostname,
      ruby_version: RUBY_VERSION,
      rails_version: Rails.version
    }
    
    # Configure sampling
    config.traces_sampler = lambda do |sampling_context|
      # Skip health checks and asset requests
      if sampling_context[:parent_sampled].nil?
        transaction_context = sampling_context[:transaction_context]
        
        # Skip certain paths
        return 0.0 if transaction_context[:name] =~ /health|assets|packs/
        
        # Sample based on request path
        case transaction_context[:name]
        when /^\/api\//
          0.2  # Sample 20% of API requests
        when /\.(css|js|jpg|png|gif|ico)$/
          0.0  # Don't sample static assets
        else
          0.1  # Sample 10% of other requests
        end
      else
        sampling_context[:parent_sampled]  # Respect parent decision
      end
    end

    # Configure performance monitoring hooks
    config.rails.register_transaction_hook do |event, hint|
      case event.name
      when 'sql.active_record'
        duration = event.duration
        if duration > 1000 # 1 second
          Sentry.add_breadcrumb(
            Sentry::Breadcrumb.new(
              category: 'sql',
              message: 'Slow SQL query',
              data: {
                sql: event.payload[:sql],
                duration: duration,
                name: event.payload[:name]
              },
              level: duration > 5000 ? 'warning' : 'info'
            )
          )
        end
      when 'process_action.action_controller'
        if event.payload[:view_runtime].to_f > 1000 || event.payload[:db_runtime].to_f > 1000
          Sentry.add_breadcrumb(
            Sentry::Breadcrumb.new(
              category: 'performance',
              message: 'Slow controller action',
              data: {
                controller: event.payload[:controller],
                action: event.payload[:action],
                view_runtime: event.payload[:view_runtime],
                db_runtime: event.payload[:db_runtime]
              },
              level: 'warning'
            )
          )
        end
      end
    end

    # Ignore common timeouts and background noise
    config.excluded_exceptions += [
      'ActionController::RoutingError',
      'ActiveRecord::RecordNotFound',
      'ActionController::InvalidAuthenticityToken',
      'ActionDispatch::Http::Parameters::ParseError',
      'ActionController::BadRequest',
      'ActionController::ParameterMissing',
      'Rack::Timeout::RequestTimeoutException'
    ]

    # Configure performance monitoring thresholds
    config.traces_sample_rate = Rails.env.production? ? 0.1 : 1.0
    config.profiles_sample_rate = Rails.env.production? ? 0.1 : 1.0
    
    # Add custom instrumentation
    config.auto_instrument_redis = true
    config.auto_instrument_http = true
    config.auto_instrument_cache = true
    
    # Integration with rack-timeout
    if defined?(Rack::Timeout)
      config.traces_ignorer = lambda do |trace_context|
        trace_context[:exception_class] == 'Rack::Timeout::RequestTimeoutException'
      end
    end

    # Add custom context processors
    config.before_send_transaction = lambda do |event|
      # Add custom performance metrics
      event.contexts[:performance] = {
        memory_usage: `ps -o rss= -p #{Process.pid}`.to_i / 1024,
        process_id: Process.pid,
        thread_count: Thread.list.count,
        gc_stat: GC.stat.slice(:count, :heap_allocated_pages, :heap_sorted_length)
      }
      event
    end
  end
  
  # Set up error monitoring for Sidekiq if it's being used
  if defined?(Sidekiq)
    config.sidekiq.report_after_job_retries = true
    
    Sidekiq.configure_server do |config|
      config.error_handlers << proc do |ex, ctx|
        Sentry.with_scope do |scope|
          scope.set_extras(ctx)
          scope.set_transaction_name("Sidekiq: #{ctx['class']}")
          Sentry.capture_exception(ex)
        end
      end
    end
  end
  
  # Add custom context processors
  Sentry.add_context_processor do
    {
      memory_usage: `ps -o rss= -p #{Process.pid}`.to_i / 1024, # Convert to MB
      process_id: Process.pid,
      thread_count: Thread.list.count
    }
  end
  
  # Set up error reporting for database connection issues
  ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    if event.duration > 5000 # 5 seconds
      Sentry.capture_message(
        "Very slow SQL query detected",
        level: 'warning',
        extra: {
          sql: event.payload[:sql],
          name: event.payload[:name],
          duration: event.duration,
          connection_pool: {
            size: ActiveRecord::Base.connection_pool.size,
            active: ActiveRecord::Base.connection_pool.connections.count(&:in_use?),
            waiting: ActiveRecord::Base.connection_pool.num_waiting_in_queue
          }
        }
      )
    end
  rescue => e
    Rails.logger.error("Failed to report SQL performance issue: #{e.message}")
  end
end