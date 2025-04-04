class TestJob < ApplicationJob
  queue_as :default
  
  def perform(message = nil)
    Rails.logger.info "Test job running at #{Time.current} with message: #{message}"
  end
end