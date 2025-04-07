# frozen_string_literal: true

# Comprehensive database connection management
# This file consolidates all database connection management logic

# Configure PostgreSQL connection pool
ActiveSupport.on_load(:active_record) do
  # Set up connection pool based on environment
  pool_size = case Rails.env
              when 'development'
                ENV.fetch('RAILS_MAX_THREADS', 2).to_i
              when 'test'
                5
              when 'production'
                ENV.fetch('RAILS_MAX_THREADS', 5).to_i
              else
                2
              end

  # Configure ActiveRecord connection pool
  ActiveRecord::Base.connection_pool.disconnect!

  # Set the connection pool size in database.yml
  ENV['RAILS_MAX_THREADS'] = pool_size.to_s

  # Establish a new connection with the updated pool size
  ActiveRecord::Base.establish_connection

  # Log configuration
  Rails.logger.info "PostgreSQL connection pool configured with size: #{pool_size}"

  # Force all threads to disconnect when forking
  if Process.respond_to?(:fork)
    ActiveRecord::Base.connection_pool.disconnect! if Process.pid != $$
  end
end

# Cleanup idle connections periodically
if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
      ActiveRecord::Base.establish_connection
    end
  end
end

# Clear connections after processing each request
Rails.application.config.after_initialize do
  ActiveRecord::Base.connection_pool.disconnect!
  ActiveSupport.on_load(:after_initialize) do
    ApplicationController.after_action do
      ActiveRecord::Base.connection_pool.release_connection
    end
  end

  # Set specific pool sizes for background processes
  if defined?(Rails::Server)
    Rails.logger.info "Setting connection pool size for web server"
  elsif defined?(Rails::Console)
    ActiveRecord::Base.connection_pool.disconnect!
    ActiveRecord::Base.establish_connection(
      ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).first
        .configuration_hash.merge(pool: 1)
    )
    Rails.logger.info "Limited console connection pool to 1"
  end

  # Set up periodic connection cleanup
  if Rails.env.development? || Rails.env.production?
    # Clean up connections periodically
    Thread.new do
      loop do
        begin
          sleep ENV.fetch('DB_CLEANUP_INTERVAL', 600).to_i # 10 minutes
          ActiveRecord::Base.connection_pool.disconnect!
          ActiveRecord::Base.connection_pool.clear_reloadable_connections!
          ActiveRecord::Base.clear_active_connections!

          # Kill idle connections at the PostgreSQL level
          begin
            # Get the current database name
            db_name = ActiveRecord::Base.connection.current_database

            # Kill idle connections that have been idle for more than 5 minutes
            ActiveRecord::Base.connection.execute(<<-SQL)
              SELECT pg_terminate_backend(pid)
              FROM pg_stat_activity
              WHERE datname = '#{db_name}'
              AND pid <> pg_backend_pid()
              AND state = 'idle'
              AND (now() - state_change) > interval '5 minutes';
            SQL
          rescue => e
            Rails.logger.error "Error cleaning up PostgreSQL connections: #{e.message}"
          end
        rescue => e
          Rails.logger.error "Error in connection cleanup thread: #{e.message}"
        end
      end
    end
  end
end