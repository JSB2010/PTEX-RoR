# frozen_string_literal: true

require 'socket'

module ProcessManager
  class << self
    def start_services
      # Skip in test environment or when using foreman
      return if Rails.env.test? || ENV['FOREMAN'] || ENV['FOREMAN_WORKER_NAME']
      
      # Only start background processes if explicitly requested
      start_background_processes if ENV['START_BACKGROUND_PROCESSES']
    end

    def stop_services
      return unless defined?(SolidQueue)
      SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)
    end

    private

    def start_background_processes
      return unless defined?(SolidQueue)
      config = SolidQueue::Configuration.new
      supervisor = SolidQueue::Supervisor.new(config)
      
      Rails.logger.info "Starting SolidQueue background processes..."
      supervisor.start
      Rails.logger.info "SolidQueue processes started successfully"
    rescue => e
      Rails.logger.error "Failed to start SolidQueue processes: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end
end

# DISABLED: This was causing recursive process spawning
# Start background processes after Rails initialization
# Rails.application.config.after_initialize do
#   ProcessManager.start_services unless Rails.env.test? || defined?(Rails::Console)
# end