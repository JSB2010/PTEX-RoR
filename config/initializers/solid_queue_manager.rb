require 'solid_queue_manager'

# Initialize SolidQueue after Rails is fully loaded
Rails.application.config.after_initialize do
  # Only initialize SolidQueue in development mode
  if Rails.env.development?
    begin
      # Check if we should start SolidQueue processes
      if defined?(SolidQueueManager) && SolidQueueManager.should_start_processes?
        # Initialize SolidQueue
        SolidQueueManager.initialize_solid_queue
      end
    rescue => e
      Rails.logger.error "Error initializing SolidQueue: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end
