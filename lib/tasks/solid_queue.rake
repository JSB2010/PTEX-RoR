namespace :solid_queue do
  desc "Start all SolidQueue processes"
  task start: :environment do
    begin
      script_path = Rails.root.join('bin', 'start-solid-queue')
      if File.exist?(script_path) && File.executable?(script_path)
        puts "Starting SolidQueue using #{script_path}..."
        system(script_path.to_s)
      else
        puts "SolidQueue start script not found or not executable at #{script_path}"
        puts "Making script executable..."
        FileUtils.chmod('+x', script_path) if File.exist?(script_path)

        if File.exist?(script_path) && File.executable?(script_path)
          puts "Starting SolidQueue using #{script_path}..."
          system(script_path.to_s)
        else
          puts "ERROR: Could not make script executable. Using fallback method."

          # Fallback to direct process creation
          FileUtils.mkdir_p(Rails.root.join("tmp", "pids"))

          # Clean up any existing processes
          system("pkill -f 'solid_queue_(worker|dispatcher)' || true")
          SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)

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
        end
      end
    rescue => e
      puts "Failed to start SolidQueue processes: #{e.message}"
      puts e.backtrace
      raise e
    end
  end

  desc "Stop all SolidQueue processes"
  task stop: :environment do
    begin
      script_path = Rails.root.join('bin', 'stop-solid-queue')
      if File.exist?(script_path) && File.executable?(script_path)
        puts "Stopping SolidQueue using #{script_path}..."
        system(script_path.to_s)
      else
        puts "SolidQueue stop script not found or not executable at #{script_path}"
        puts "Making script executable..."
        FileUtils.chmod('+x', script_path) if File.exist?(script_path)

        if File.exist?(script_path) && File.executable?(script_path)
          puts "Stopping SolidQueue using #{script_path}..."
          system(script_path.to_s)
        else
          puts "ERROR: Could not make script executable. Using fallback method."

          # Fallback to direct process termination
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
        end
      end
    rescue => e
      puts "Error stopping SolidQueue processes: #{e.message}"
      puts e.backtrace
    end
  end

  desc "Restart all SolidQueue processes"
  task restart: :environment do
    Rake::Task["solid_queue:stop"].invoke
    sleep 2 # Give processes time to fully stop
    Rake::Task["solid_queue:start"].invoke
  end

  desc "Check status of SolidQueue processes"
  task status: :environment do
    begin
      # Check if processes are running
      dispatcher_running = false
      worker_running = false

      # Check by PID files
      %w[worker dispatcher].each do |type|
        pid_file = Rails.root.join("tmp/pids/solid_queue_#{type}.pid")
        if File.exist?(pid_file)
          pid = File.read(pid_file).strip.to_i
          if pid > 0
            running = system("ps -p #{pid} > /dev/null")
            puts "SolidQueue #{type} (PID: #{pid}): #{running ? 'RUNNING' : 'NOT RUNNING'}"
            dispatcher_running = true if type == 'dispatcher' && running
            worker_running = true if type == 'worker' && running
          else
            puts "SolidQueue #{type}: NOT RUNNING (invalid PID)"
          end
        else
          puts "SolidQueue #{type}: NOT RUNNING (no PID file)"
        end
      end

      # Check for processes without PID files
      if system("pgrep -f 'SolidQueue::Dispatcher' > /dev/null")
        puts "Found SolidQueue dispatcher processes without PID files" unless dispatcher_running
        dispatcher_running = true
      end

      if system("pgrep -f 'SolidQueue::Worker' > /dev/null")
        puts "Found SolidQueue worker processes without PID files" unless worker_running
        worker_running = true
      end

      # Check database status
      if defined?(SolidQueue::Process) && ActiveRecord::Base.connection.table_exists?('solid_queue_processes')
        hostname = Socket.gethostname
        processes = SolidQueue::Process.where(hostname: hostname)
        puts "\nDatabase records for host #{hostname}:"
        if processes.any?
          processes.each do |process|
            puts "  #{process.kind} (#{process.name}): PID #{process.pid}, last heartbeat: #{process.last_heartbeat_at}"
          end
        else
          puts "  No process records found"
        end

        # Check job counts
        puts "\nJob counts:"
        puts "  Ready jobs: #{SolidQueue::ReadyExecution.count}"
        puts "  Scheduled jobs: #{SolidQueue::ScheduledExecution.count}"
        puts "  Claimed jobs: #{SolidQueue::ClaimedExecution.count}"
        puts "  Failed jobs: #{SolidQueue::Job.where.not(failed_at: nil).count}"
        puts "  Completed jobs: #{SolidQueue::Job.where.not(finished_at: nil).where(failed_at: nil).count}"
      else
        puts "\nCannot check database status: SolidQueue tables not found"
      end

      # Overall status
      puts "\nOverall status: #{dispatcher_running && worker_running ? 'RUNNING' : 'NOT RUNNING'}"
    rescue => e
      puts "Error checking SolidQueue status: #{e.message}"
      puts e.backtrace
    end
  end
end
