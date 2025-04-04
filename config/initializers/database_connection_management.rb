# Force all threads to disconnect when forking
ActiveSupport.on_load(:active_record) do
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