class CleanupLogsJob < ApplicationJob
  queue_as :maintenance

  def perform
    log_dir = Rails.root.join('log')
    cutoff_time = 24.hours.ago

    # Handle regular log files
    Dir.glob("#{log_dir}/*").each do |file|
      next if File.directory?(file)
      next if file.end_with?('.keep')
      
      if File.mtime(file) < cutoff_time
        Rails.logger.info "Removing old log file: #{file}"
        File.delete(file)
      end
    end

    # Specifically handle Puma logs
    handle_puma_logs(log_dir)
  end

  private

  def handle_puma_logs(log_dir)
    puma_logs = ['puma.stdout.log', 'puma.stderr.log']
    
    puma_logs.each do |log_name|
      log_path = log_dir.join(log_name)
      
      if File.exist?(log_path) && File.size(log_path) > 50.megabytes
        Rails.logger.info "Truncating large Puma log: #{log_name}"
        
        # Keep only the last 1000 lines
        begin
          content = File.readlines(log_path).last(1000).join
          File.write(log_path, content)
        rescue => e
          Rails.logger.error "Failed to truncate #{log_name}: #{e.message}"
        end
      end
    end
  end
end
