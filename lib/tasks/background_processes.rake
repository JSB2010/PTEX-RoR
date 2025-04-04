namespace :background_processes do
  desc "Start background processes (worker and dispatcher)"
  task start: :environment do
    if pid = fork
      # Parent process
      Process.detach(pid)
      puts "Background processes started with PID #{pid}"
    else
      # Child process
      begin
        # Set up worker
        worker_process = SolidQueue::Process.create!(
          kind: "Worker",
          name: "worker-#{SecureRandom.hex(6)}",
          hostname: Socket.gethostname,
          pid: Process.pid,
          metadata: {
            queues: ENV.fetch("SOLID_QUEUE_QUEUES", "default,mailers,active_storage,maintenance").split(",")
          }
        )

        # Set up dispatcher
        dispatcher_process = SolidQueue::Process.create!(
          kind: "Dispatcher",
          name: "dispatcher-#{SecureRandom.hex(6)}",
          hostname: Socket.gethostname,
          pid: Process.pid,
          metadata: {}
        )

        running = true
        trap("TERM") { running = false }
        trap("INT") { running = false }

        # Main process loop
        while running
          begin
            worker_process.update!(last_heartbeat_at: Time.current)
            dispatcher_process.update!(last_heartbeat_at: Time.current)
            
            # Run worker and dispatcher once
            SolidQueue::Worker.new(worker_process).run_once
            SolidQueue::Dispatcher.new(dispatcher_process).run_once
            
            sleep(ENV.fetch("SOLID_QUEUE_POLLING_INTERVAL", "0.1").to_f)
          rescue => e
            Rails.logger.error "Background process error: #{e.class} - #{e.message}"
            sleep 1
          end
        end
      ensure
        # Clean up
        [worker_process, dispatcher_process].each do |process|
          process&.deregister if process&.persisted?
        end
      end
    end
  end

  desc "Stop background processes"
  task stop: :environment do
    SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)
  end
end