# frozen_string_literal: true

class TestFailedAtJob < ApplicationJob
  queue_as :default

  def perform
    # This job will always fail
    raise "This job is designed to fail to test the failed_at column"
  end
end
