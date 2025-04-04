require 'connection_pool'

redis_config = {
  url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
  size: Integer(ENV.fetch('REDIS_MAX_THREADS', 10)),
  timeout: Rails.env.development? ? 15 : 5,
  reconnect_attempts: 3,
  error_handler: -> (method:, returning:, exception:) {
    Rails.logger.error("Redis cache error: #{exception.class}: #{exception.message}")
    Sentry.capture_exception(exception) if defined?(Sentry)
  }
}

# Configure Redis connection pool
redis_pool = ConnectionPool.new(size: redis_config[:size], timeout: redis_config[:timeout]) do
  Redis.new(
    url: redis_config[:url],
    reconnect_attempts: redis_config[:reconnect_attempts],
    connect_timeout: Rails.env.development? ? 5 : 1,
    read_timeout: Rails.env.development? ? 5 : 0.5,
    write_timeout: Rails.env.development? ? 5 : 0.5
  )
end

# Make Redis client available globally and in Rails config
$redis = redis_pool
Rails.application.config.redis_client = redis_pool

# Configure cache store for Rails
Rails.application.config.cache_store = :redis_cache_store, {
  pool: redis_pool,
  error_handler: redis_config[:error_handler],
  namespace: "ptex:#{Rails.env}:"
}