# frozen_string_literal: true

module SolidQueue
  class Record < ApplicationRecord
    self.abstract_class = true

    def non_blocking_lock
      yield self
    end

    def self.transaction_with_retry(attempts: 3)
      retry_count = 0
      begin
        transaction do
          yield
        end
      rescue ActiveRecord::StatementInvalid => e
        retry_count += 1
        if retry_count < attempts && e.message =~ /deadlock|lock timeout/i
          sleep(rand * 0.1)
          retry
        else
          raise
        end
      end
    end
  end
end