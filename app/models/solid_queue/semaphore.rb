module SolidQueue
  class Semaphore < SolidQueue::Record
    self.table_name = "solid_queue_semaphores"
    
    def self.acquire(key:, value: 1, expires_in: 1.day)
      create_or_find_by(key: key) do |semaphore|
        semaphore.value = value
        semaphore.expires_at = Time.current + expires_in
      end
    end

    def release
      destroy
    end

    def non_blocking_lock
      yield self
    end
  end
end