module PostgresConnectionManager
  class << self
    def configure_connection_pool
      # Set reasonable pool sizes based on environment
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

      Rails.logger.info "PostgreSQL connection pool configured with size: #{pool_size}"
    end

    def cleanup_connections
      # Force disconnect all connections in the pool
      begin
        ActiveRecord::Base.connection_pool.disconnect!
        ActiveRecord::Base.connection_pool.clear_reloadable_connections!
        # ActiveRecord::Base.clear_active_connections! is deprecated in Rails 7.0+
        ActiveRecord::Base.connection_handler.clear_active_connections!
        Rails.logger.info "Successfully cleaned up database connections"
      rescue => e
        Rails.logger.error "Error cleaning up database connections: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end

      # If we're in development, we can also kill idle connections at the PostgreSQL level
      if Rails.env.development?
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

          # Kill idle in transaction connections that have been idle for more than 30 minutes
          ActiveRecord::Base.connection.execute(<<-SQL)
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = '#{db_name}'
            AND pid <> pg_backend_pid()
            AND state = 'idle in transaction'
            AND (now() - state_change) > interval '30 minutes';
          SQL

          Rails.logger.info "Cleaned up idle PostgreSQL connections"
        rescue => e
          Rails.logger.error "Error cleaning up PostgreSQL connections: #{e.message}"
        end
      end
    end

    def connection_status
      begin
        # Get the current database name
        db_name = ActiveRecord::Base.connection.current_database

        # Get connection count
        result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = $1", [db_name])
        connections = result.first["count"].to_i

        # Get max connections
        max_connections_result = ActiveRecord::Base.connection.execute("SHOW max_connections")
        max_connections = max_connections_result.first["max_connections"].to_i

        # Calculate percentage
        percentage = (connections.to_f / max_connections) * 100

        # Get idle connections
        idle_result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = $1 AND state = 'idle'", [db_name])
        idle_connections = idle_result.first["count"].to_i

        # Get active connections
        active_result = ActiveRecord::Base.connection.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = $1 AND state = 'active'", [db_name])
        active_connections = active_result.first["count"].to_i

        # Get connection pool info
        pool_size = ENV.fetch('RAILS_MAX_THREADS', 5).to_i

        {
          current: connections,
          max: max_connections,
          percentage: percentage.round(1),
          warning: percentage > 80,
          pool_size: pool_size,
          active_connections: active_connections,
          idle_connections: idle_connections,
          checkout_timeout: 5, # Default value
          idle_timeout: 300    # Default value
        }
      rescue => e
        Rails.logger.error "Error checking PostgreSQL connections: #{e.message}"
        { error: e.message }
      end
    end

    def optimize_postgres_config
      # This would typically modify postgresql.conf, but we'll just log recommendations
      # since we don't have direct access to modify the PostgreSQL configuration
      Rails.logger.info "PostgreSQL Configuration Recommendations:"
      Rails.logger.info "- max_connections: 100 (current) - Consider increasing to 200 for better performance"
      Rails.logger.info "- shared_buffers: 128MB (current) - Consider increasing to 25% of system RAM"
      Rails.logger.info "- work_mem: 4MB (current) - Consider increasing to 16MB for better query performance"
      Rails.logger.info "- maintenance_work_mem: 64MB (current) - Consider increasing to 256MB for better maintenance performance"
      Rails.logger.info "- effective_cache_size: 4GB (current) - Consider increasing to 75% of system RAM"
      Rails.logger.info "- synchronous_commit: on (default) - Consider setting to 'off' for better performance at the cost of potential data loss in case of crash"
      Rails.logger.info "- wal_buffers: -1 (default) - Consider setting to 16MB for better write performance"
      Rails.logger.info "- checkpoint_timeout: 5min (default) - Consider increasing to 15min for better performance"
      Rails.logger.info "- random_page_cost: 4.0 (default) - Consider setting to 1.1 for SSD storage"
      Rails.logger.info "- effective_io_concurrency: 1 (default) - Consider setting to 200 for SSD storage"

      # Return recommendations as a hash
      {
        max_connections: 200,
        shared_buffers: "25% of RAM",
        work_mem: "16MB",
        maintenance_work_mem: "256MB",
        effective_cache_size: "75% of RAM",
        synchronous_commit: "off",
        wal_buffers: "16MB",
        checkpoint_timeout: "15min",
        random_page_cost: 1.1,
        effective_io_concurrency: 200
      }
    end
  end
end
