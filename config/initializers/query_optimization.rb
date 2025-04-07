# frozen_string_literal: true

# Database query optimization
#
# This initializer sets up database query optimization to improve performance.

# Enable query cache in all environments
ActiveRecord::Base.connection.enable_query_cache!

# Set up query logging in development
if Rails.env.development?
  # Log slow queries
  ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, start, finish, _id, payload|
    duration = (finish - start) * 1000 # Convert to milliseconds

    # Log queries that take longer than 100ms
    if duration > 100 && !payload[:name].in?(['SCHEMA', 'EXPLAIN', 'CACHE'])
      Rails.logger.warn "SLOW QUERY (#{duration.round(2)}ms): #{payload[:sql]}"
    end
  end

  # Log N+1 queries
  if defined?(Bullet)
    Bullet.enable = true
    Bullet.alert = true
    Bullet.bullet_logger = true
    Bullet.console = true
    Bullet.rails_logger = true
    Bullet.add_footer = true
  end
end

# Set up query optimization in production
if Rails.env.production?
  # Log slow queries
  ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, start, finish, _id, payload|
    duration = (finish - start) * 1000 # Convert to milliseconds

    # Log queries that take longer than 500ms
    if duration > 500 && !payload[:name].in?(['SCHEMA', 'EXPLAIN', 'CACHE'])
      Rails.logger.warn "SLOW QUERY (#{duration.round(2)}ms): #{payload[:sql]}"
    end
  end
end

# Monkey patch ActiveRecord to add query optimization
module ActiveRecord
  module QueryOptimization
    # Add index hints to queries
    def with_index_hint(index_name)
      from("#{table_name} USE INDEX (#{index_name})")
    end

    # Force index usage
    def force_index(index_name)
      from("#{table_name} FORCE INDEX (#{index_name})")
    end

    # Add query timeout
    def with_timeout(seconds)
      if connection.adapter_name =~ /mysql/i
        connection.execute("SET SESSION MAX_EXECUTION_TIME = #{(seconds * 1000).to_i}")
        result = yield
        connection.execute("SET SESSION MAX_EXECUTION_TIME = 0")
        result
      elsif connection.adapter_name =~ /postgresql/i
        connection.execute("SET statement_timeout = #{(seconds * 1000).to_i}")
        result = yield
        connection.execute("SET statement_timeout = 0")
        result
      else
        yield
      end
    end

    # Add query priority
    def with_low_priority
      if connection.adapter_name =~ /mysql/i
        connection.execute("SET SESSION TRANSACTION PRIORITY LOW")
        result = yield
        connection.execute("SET SESSION TRANSACTION PRIORITY NORMAL")
        result
      else
        yield
      end
    end
  end
end

# Include the query optimization module in ActiveRecord::Relation
ActiveRecord::Relation.include(ActiveRecord::QueryOptimization)

# Set up database statement cache size if available
if ActiveRecord::Base.connection.respond_to?(:statement_cache) && ActiveRecord::Base.connection.statement_cache
  ActiveRecord::Base.connection.statement_cache.instance_variable_set(:@max_size, ENV.fetch('STATEMENT_CACHE_SIZE', 1000).to_i)
end

# Set up prepared statement cache size if available
if ActiveRecord::Base.connection.respond_to?(:prepared_statements_cache) && ActiveRecord::Base.connection.prepared_statements_cache
  ActiveRecord::Base.connection.prepared_statements_cache.instance_variable_set(:@max_size, ENV.fetch('PREPARED_STATEMENTS_CACHE_SIZE', 1000).to_i)
end
