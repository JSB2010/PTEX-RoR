require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in either ENV["RAILS_MASTER_KEY"]
  # or in config/master.key. This key is used to decrypt credentials (and other encrypted files).
  config.require_master_key = true

  # Configure job processing
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
  config.active_job.retry_jitter = 0.15
  config.active_job.verbose_enqueue_logs = true

  # Disable serving static files from the `/public` folder by default since
  # Apache or NGINX already handles this.
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  config.asset_host = ENV["ASSET_HOST"]

  # Specifies the header that your server uses for sending files.
  config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Compress CSS using a preprocessor.
  config.assets.css_compressor = :sass
  config.assets.js_compressor = :terser

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Enable serving static files with an efficient cache control.
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.year.to_i}"
  }

  # Use Redis for caching
  # Optimized Redis cache configuration
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" },
    namespace: "ptex:cache:#{Rails.env}",
    expires_in: ENV.fetch("CACHE_EXPIRES_IN", 7.days).to_i,
    compress: true,
    compression_threshold: 1.kilobyte,
    pool_size: ENV.fetch("REDIS_POOL_SIZE", 10).to_i,
    pool_timeout: ENV.fetch("REDIS_POOL_TIMEOUT", 5).to_i,
    reconnect_attempts: 3,
    error_handler: -> (method:, returning:, exception:) {
      Rails.logger.error "Redis cache error: #{exception.message}"
      Honeybadger.notify(exception) if defined?(Honeybadger)
    }
  }

  # Enable HTTP caching
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{ENV.fetch('CACHE_MAX_AGE', 86400)}"
  }

  # Enable low-level caching
  config.action_controller.perform_caching = true
  config.action_view.cache_template_loading = true

  # Use a real mailer backend
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV["SMTP_SERVER"],
    port: ENV["SMTP_PORT"],
    user_name: ENV["SMTP_USERNAME"],
    password: ENV["SMTP_PASSWORD"],
    authentication: :plain,
    enable_starttls_auto: true
  }

  # Enable locale fallbacks for I18n
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Log disallowed deprecations.
  config.active_support.disallowed_deprecation = :log

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Use a different logger for distributed setups.
  # require "syslog/logger"
  # config.logger = ActiveSupport::TaggedLogging.new(Syslog::Logger.new "app-name")

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger           = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  # Enable lograge for better logging
  config.lograge.enabled = true
  config.lograge.custom_options = lambda do |event|
    { time: event.time }
  end

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other Host header attacks.
  config.hosts = ENV.fetch("ALLOWED_HOSTS") { "" }.split(",")

  # Enable HTTP/2 Early Hints
  config.action_dispatch.send_early_hints = true

  # Enable rack-attack for rate limiting and blocking malicious requests
  config.middleware.use Rack::Attack

  # Enable request decompression
  config.middleware.use Rack::Deflater

  # Configure logger to rotate logs
  config.logger = ActiveSupport::Logger.new(
    config.paths["log"].first,
    1, # number of old logs to keep
    50.megabytes # max log size
  )
end

# Configure rack-attack rate limiting
Rack::Attack.throttle("requests by ip", limit: 300, period: 5.minutes) do |request|
  request.ip
end
