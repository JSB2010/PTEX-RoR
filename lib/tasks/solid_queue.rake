namespace :solid_queue do
  desc "Start all SolidQueue processes"
  task start: :environment do
    FileUtils.mkdir_p(Rails.root.join("tmp", "pids"))
    
    # Clean up any existing processes
    system("pkill -f 'solid_queue_(worker|dispatcher)' || true")
    SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)
    
    begin
      # Load configuration with aliases enabled
      config = if File.exist?(Rails.root.join('config', 'queue.yml'))
        YAML.load_file(Rails.root.join('config', 'queue.yml'), aliases: true)[Rails.env].deep_symbolize_keys
      else
        { polling_interval: 0.5, concurrency: 5, queues: ['default'] }
      end

      # Start worker process
      worker_pid = fork do
        $0 = "solid_queue_worker"
        begin
          worker = SolidQueue::Worker.new(
            queues: config[:queues] || ['default'],
            threads: config[:concurrency] || 5,
            polling_interval: config[:polling_interval] || 0.5,
            batch_size: config[:batch_size] || 100,
            name: "worker-#{SecureRandom.hex(6)}"
          )
          worker.start
        rescue StandardError => error
          puts "Worker Error: #{error.message}"
          raise error
        end
      end

      # Start dispatcher process
      dispatcher_pid = fork do
        $0 = "solid_queue_dispatcher"
        begin
          dispatcher = SolidQueue::Dispatcher.new(
            polling_interval: config.dig(:dispatcher, :polling_interval) || 0.5,
            batch_size: config.dig(:dispatcher, :batch_size) || 100,
            name: "dispatcher-#{SecureRandom.hex(6)}"
          )
          dispatcher.start
        rescue StandardError => error
          puts "Dispatcher Error: #{error.message}"
          raise error
        end
      end
      
      # Write PIDs and detach processes
      File.write(Rails.root.join("tmp/pids/solid_queue_worker.pid"), worker_pid)
      File.write(Rails.root.join("tmp/pids/solid_queue_dispatcher.pid"), dispatcher_pid)
      Process.detach(worker_pid)
      Process.detach(dispatcher_pid)
      
      puts "Started SolidQueue worker (PID: #{worker_pid}) and dispatcher (PID: #{dispatcher_pid})"
    rescue => e
      puts "Failed to start SolidQueue processes: #{e.message}"
      puts e.backtrace
      raise e
    end
  end

  desc "Stop all SolidQueue processes"
  task stop: :environment do
    begin
      # Try to stop by PID first
      %w[worker dispatcher].each do |type|
        pid_file = Rails.root.join("tmp/pids/solid_queue_#{type}.pid")
        if File.exist?(pid_file)
          pid = File.read(pid_file).strip
          if pid.present?
            puts "Stopping SolidQueue #{type} (PID: #{pid})..."
            system("kill -TERM #{pid} 2>/dev/null")
          end
          File.delete(pid_file)
        end
      end

      # Cleanup any remaining processes
      system("pkill -TERM -f 'solid_queue_(worker|dispatcher)' 2>/dev/null || true")
      sleep 2 # Give processes time to shutdown gracefully
      system("pkill -KILL -f 'solid_queue_(worker|dispatcher)' 2>/dev/null || true")

      # Clean up database records
      if defined?(SolidQueue::Process)
        SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)
      end

      puts "Stopped all SolidQueue processes"
    rescue => e
      puts "Error stopping SolidQueue processes: #{e.message}"
      puts e.backtrace
    end
  end

  desc "Restart all SolidQueue processes"
  task restart: [:stop, :start]
end
