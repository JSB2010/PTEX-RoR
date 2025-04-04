# frozen_string_literal: true

module ProcessLock
  class << self
    def with_lock(name)
      lock_file = Rails.root.join('tmp', 'pids', "#{name}.lock")
      
      # Clean up stale lock if it exists
      if File.exist?(lock_file)
        pid = File.read(lock_file).to_i
        unless process_running?(pid)
          Rails.logger.info "Removing stale lock for #{name} (PID: #{pid})"
          File.delete(lock_file)
        end
      end
      
      return if File.exist?(lock_file)
      
      File.write(lock_file, Process.pid)
      begin
        yield if block_given?
      ensure
        File.delete(lock_file) if File.exist?(lock_file) && File.read(lock_file).to_i == Process.pid
      end
    end
    
    private
    
    def process_running?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
  end
end