# frozen_string_literal: true
require_relative "boot"
require "rails/all"

# Require the gems listed in Gemfile
Bundler.require(*Rails.groups)

module PtexRoR
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Autoload paths configuration
    config.autoload_lib(ignore: %w[assets tasks templates generators])

    # Time zone configuration
    config.time_zone = "UTC"
    config.eager_load_paths << Rails.root.join("lib")

    # Skip migration check if environment variable is set
    if ENV['SKIP_MIGRATION_CHECK'] == 'true'
      config.paths['db/migrate'] = []
    end

    # Configure migration settings
    config.after_initialize do
      # Skip migrations in development mode if requested
      if ENV['SKIP_MIGRATION_CHECK'] == 'true' && defined?(ActiveRecord::Migration)
        # Monkey patch the migration check to always return empty array
        ActiveRecord::Migration.singleton_class.prepend(Module.new do
          def check_pending!
            # Do nothing
          end

          def migrations_paths
            []
          end

          def migrations_status
            []
          end
        end)
      end
    end

    # Active Job configuration
    if ENV['SKIP_SOLID_QUEUE'] == 'true'
      config.active_job.queue_adapter = :inline
    else
      begin
        # Check if SolidQueue is available
        require 'solid_queue'
        config.active_job.queue_adapter = :solid_queue
      rescue LoadError => e
        # Fall back to inline adapter if SolidQueue is not available
        Rails.logger.warn "SolidQueue not available: #{e.message}. Using inline adapter instead."
        config.active_job.queue_adapter = :inline
      end
    end

    # Redis cache store configuration
    config.cache_store = :redis_cache_store, {
      url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" },
      error_handler: -> (method:, returning:, exception:) {
        Rails.logger.error("Redis cache error: #{exception.class} - #{exception.message}")
        Sentry.capture_exception(exception) if defined?(Sentry)
      }
    }

    # Server configuration
    config.reload_classes_only_on_change = true
    config.enable_dependency_loading = true

    # Logger configuration
    config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))
    config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

    # Session store configuration
    config.session_store :cookie_store, key: '_ptex_session'

    # Database connections configuration
    config.after_initialize do
      # Set up database connection pool
      ActiveRecord::Base.connection_handler.connection_pools.each do |_, pool|
        pool.connection.reconnect! if pool&.connected?
      end

      # Configure SolidQueue connection handling
      ActiveSupport::Notifications.subscribe('solid_queue.background_task') do |*args|
        ActiveRecord::Base.connection_pool.release_connection if ActiveRecord::Base.connection_pool.active_connection?
      end
    end

    # Configure graceful shutdown
    at_exit do
      begin
        ActiveRecord::Base.connection_handler.connection_pools.each do |_, pool|
          pool.disconnect! if pool&.connected?
        end
      rescue => e
        Rails.logger.error("Error during database disconnect: #{e.message}")
      end
    end
  end
end
