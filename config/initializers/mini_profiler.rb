if defined?(Rack::MiniProfiler)
  Rack::MiniProfiler.config.tap do |config|
    # Enable in development
    config.enabled = !Rails.env.production?
    
    # Configure storage
    config.storage = Rack::MiniProfiler::MemoryStore
    config.storage_options = { path: Rails.root.join('tmp/miniprofiler') }
    
    # Set position and visibility
    config.position = 'bottom-right'
    config.start_hidden = true
    config.toggle_shortcut = 'alt+p'

    # Skip profiling for certain paths
    config.skip_paths = [
      '/assets',
      '/cable',
      '/packs',
      '\.hot-update\.js',
      '\.map'
    ]

    # Development specific settings
    if Rails.env.development?
      config.enable_advanced_debugging_tools = true
      config.skip_schema_queries = true
      
      # Skip asset requests in development
      config.skip_paths.concat([
        '/mini-profiler-resources/',
        '/favicon.ico'
      ])
    end

    # Authorization in production
    if Rails.env.production?
      config.authorization_mode = :allowlist
      config.user_provider = Proc.new { |env|
        request = Rack::Request.new(env)
        # Only show to admins in production
        user_id = request.session[:user_id]
        user_id && User.find_by(id: user_id)&.admin? ? "Admin #{user_id}" : nil
      }
    end
  end

  # Add custom timings for SQL queries
  ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    if current = Rack::MiniProfiler.current
      # Skip schema queries in dev/test
      next if Rack::MiniProfiler.config.skip_schema_queries && event.payload[:name] == "SCHEMA"
      
      # Create timing data
      request = current.current_timer
      start_millis = ((event.time - request.start) * 1000).to_f
      duration_millis = ((event.end - event.time) * 1000).to_f
      
      # Create SQL timing entry with just the required parameters
      sql_timing = Rack::MiniProfiler::TimerStruct::Sql.create(
        parent: request,
        page: current.page_struct,
        execute_type: event.payload[:name] || 'SQL',
        query: event.payload[:sql].to_s,
        start_milliseconds: start_millis,
        duration_milliseconds: duration_millis,
        params: event.payload[:binds]
      )
      
      request.sql_timings.push(sql_timing) if request.sql_timings
    end
  end
end