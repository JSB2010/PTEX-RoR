# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.

# Puma configuration for development
require "barnes" if ENV["ENABLE_RUBY_STATS"]

# Environment-specific settings
rails_env = ENV.fetch("RAILS_ENV") { "development" }
environment rails_env

# Configure thread count
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Configure workers based on environment
workers_count = ENV.fetch("WEB_CONCURRENCY") { rails_env == "development" ? 0 : 2 }.to_i
workers workers_count

# Port configuration
port ENV.fetch("PORT") { 3000 }

# Bind to Unix socket if specified
bind ENV.fetch("SOCKET") { nil } if ENV["SOCKET"]

# Configure preload setting for production only
preload_app! if rails_env == "production"

# Database connection handling - only execute if we have workers
if workers_count > 0
  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end
end

# Configure pidfile
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Enable graceful restarts
plugin :tmp_restart

# Configure logging in development
if rails_env == "development"
  stdout_redirect "log/puma.stdout.log", "log/puma.stderr.log", true
end
