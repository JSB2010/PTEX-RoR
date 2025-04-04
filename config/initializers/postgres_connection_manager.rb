require 'postgres_connection_manager'

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

  # Set up periodic connection cleanup
  if Rails.env.development?
    # Clean up connections every 10 minutes in development
    Thread.new do
      loop do
        begin
          sleep 600 # 10 minutes
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
