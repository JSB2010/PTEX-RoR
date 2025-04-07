# Load the connection handling module
require_relative '../../lib/solid_queue/connection_handling'

# Monkey patch SolidQueue classes to include connection handling
Rails.application.config.after_initialize do
  if defined?(SolidQueue::Dispatcher) && !SolidQueue::Dispatcher.included_modules.include?(SolidQueue::ConnectionHandling)
    SolidQueue::Dispatcher.include(SolidQueue::ConnectionHandling)
  end
  
  if defined?(SolidQueue::Worker) && !SolidQueue::Worker.included_modules.include?(SolidQueue::ConnectionHandling)
    SolidQueue::Worker.include(SolidQueue::ConnectionHandling)
  end
end
