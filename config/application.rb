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

    # Active Job configuration
    config.active_job.queue_adapter = :solid_queue

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
