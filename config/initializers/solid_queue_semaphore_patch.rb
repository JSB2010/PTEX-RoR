# frozen_string_literal: true

# Direct patch for SolidQueue::Semaphore to add the missing expired method
module SolidQueue
  if defined?(Semaphore)
    class Semaphore < ApplicationRecord
      # Add the expired scope directly to the class
      scope :expired, -> { where("expires_at < ?", Time.current) }
    end
  end
end