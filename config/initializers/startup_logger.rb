module StartupLogger
  class << self
    def info(message)
      write_to_all_outputs(message)
    end

    def error(message)
      write_to_all_outputs("ERROR: #{message}")
    end

    private

    def write_to_all_outputs(message)
      # Write to standard output
      puts message

      # Write to Rails logger if available
      Rails.logger.info(message) if defined?(Rails.logger)

      # Write to a specific startup log file
      log_file = Rails.root.join('log', 'startup.log')
      File.open(log_file, 'a') do |f|
        f.puts "[#{Time.current}] #{message}"
      end
    end
  end
end