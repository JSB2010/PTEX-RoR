# We're using Procfile.dev to manage processes instead
# require_relative '../../lib/background_processes/daemon_manager'

# Rails.application.config.after_initialize do
#   next unless defined?(Rails::Server)
#   BackgroundProcesses::DaemonManager.start_services
# end