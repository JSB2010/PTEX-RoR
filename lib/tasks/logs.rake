namespace :logs do
  desc 'Clean up log files older than 24 hours'
  task cleanup: :environment do
    puts "Starting log cleanup..."
    
    # Show current log sizes
    log_dir = Rails.root.join('log')
    puts "\nCurrent log sizes:"
    Dir.glob("#{log_dir}/*").each do |file|
      next if File.directory?(file)
      size_mb = File.size(file).to_f / 1.megabyte
      puts "#{File.basename(file)}: #{size_mb.round(2)} MB"
    end

    # Perform cleanup
    CleanupLogsJob.perform_now

    # Show new log sizes
    puts "\nNew log sizes:"
    Dir.glob("#{log_dir}/*").each do |file|
      next if File.directory?(file)
      size_mb = File.size(file).to_f / 1.megabyte
      puts "#{File.basename(file)}: #{size_mb.round(2)} MB"
    end
    
    puts "\nLog cleanup completed!"
  end

  desc 'Clean up log files older than specified hours (default: 24)'
  task :cleanup_older_than, [:hours] => :environment do |_t, args|
    hours = (args[:hours] || 24).to_i
    puts "Cleaning up logs older than #{hours} hours..."
    
    log_dir = Rails.root.join('log')
    cutoff_time = hours.hours.ago

    # Show current log sizes
    puts "\nCurrent log sizes:"
    Dir.glob("#{log_dir}/*").each do |file|
      next if File.directory?(file)
      size_mb = File.size(file).to_f / 1.megabyte
      puts "#{File.basename(file)}: #{size_mb.round(2)} MB"
    end

    Dir.glob("#{log_dir}/*").each do |file|
      next if File.directory?(file)
      next if file.end_with?('.keep')
      
      if File.mtime(file) < cutoff_time
        puts "Removing old log file: #{file}"
        File.delete(file)
      end
    end
    
    # Handle Puma logs specifically
    CleanupLogsJob.new.send(:handle_puma_logs, log_dir)

    # Show new log sizes
    puts "\nNew log sizes:"
    Dir.glob("#{log_dir}/*").each do |file|
      next if File.directory?(file)
      size_mb = File.size(file).to_f / 1.megabyte
      puts "#{File.basename(file)}: #{size_mb.round(2)} MB"
    end
    
    puts "\nLog cleanup completed!"
  end
end
