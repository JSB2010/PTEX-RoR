# Minimal Puma configuration

# Environment-specific settings
environment ENV.fetch("RAILS_ENV") { "development" }

# Thread configuration
threads ENV.fetch("RAILS_MIN_THREADS") { 1 }, ENV.fetch("RAILS_MAX_THREADS") { 5 }

# Worker configuration (0 for development)
workers ENV.fetch("WEB_CONCURRENCY") { 0 }

# Port configuration
port ENV.fetch("PORT") { 3000 }

# Configure pidfile
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Enable graceful restarts
plugin :tmp_restart

# Configure worker timeout
worker_timeout 60

# Configure worker boot timeout
worker_boot_timeout 60

# Configure before fork
before_fork do
  # Close connections to avoid connection leaks
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)

  # Run garbage collection before forking
  GC.start if defined?(GC)
end

# Configure after fork
on_worker_boot do
  # Re-establish connections
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)

  # Initialize Redis connection pool if Redis is used
  if defined?(Redis) && ENV['REDIS_URL'].present?
    $redis = Redis.new(url: ENV['REDIS_URL'])
  end
end
