require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    # Use Redis for caching if available
    if ENV["REDIS_URL"].present?
      config.cache_store = :redis_cache_store, {
        url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" },
        namespace: "ptex:cache:#{Rails.env}",
        expires_in: ENV.fetch("CACHE_EXPIRES_IN", 1.hour).to_i,
        compress: true,
        compression_threshold: 1.kilobyte,
        pool_size: ENV.fetch("REDIS_POOL_SIZE", 5).to_i,
        pool_timeout: ENV.fetch("REDIS_POOL_TIMEOUT", 5).to_i,
        error_handler: -> (method:, returning:, exception:) {
          Rails.logger.error "Redis cache error: #{exception.message}"
        }
      }

      # Enable low-level caching
      config.action_controller.perform_caching = true
      config.action_view.cache_template_loading = true

      # Enable HTTP caching
      config.public_file_server.headers = {
        'Cache-Control' => "public, max-age=#{ENV.fetch('CACHE_MAX_AGE', 3600)}"
      }
    else
      # Fall back to memory store if Redis is not available
      config.cache_store = :memory_store, { size: 64.megabytes }
    end
  else
    config.action_controller.perform_caching = false
    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
  config.active_support.disallowed_deprecation_warnings = []

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_job.verbose_enqueue_logs = true

  # Enable debug logging
  config.log_level = :debug
  config.log_formatter = ::Logger::Formatter.new

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  # Temporarily disable Bullet for troubleshooting
  config.after_initialize do
    # Bullet config commented out for now
    # Bullet.enable = true
    # ... other Bullet settings ...
  end

  # Basic development settings
  config.action_view.annotate_rendered_view_with_filenames = true
  config.action_controller.raise_on_missing_callback_actions = true
  config.hosts.clear # Allow all hosts in development
end
