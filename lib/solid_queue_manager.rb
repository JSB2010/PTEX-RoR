module SolidQueueManager
  class << self
    def initialize_solid_queue
      Rails.logger.info "Initializing SolidQueue..."

      # Check disk space before starting
      disk_space = check_disk_space
      if disk_space && disk_space[:warning]
        Rails.logger.warn "Disk space is critically low (#{disk_space[:percentage]}% used). This may cause issues with SolidQueue."
        # Clean up log files
        system("#{Rails.root}/bin/clean_logs.sh")
      end

      # Check PostgreSQL connections
      pg_connections = PostgresConnectionManager.connection_status
      if pg_connections[:warning]
        Rails.logger.warn "PostgreSQL connections are high (#{pg_connections[:percentage]}%). This may cause issues with SolidQueue."
        PostgresConnectionManager.cleanup_connections

        # Check again after cleanup
        pg_connections = PostgresConnectionManager.connection_status
        if pg_connections[:warning]
          Rails.logger.warn "PostgreSQL connections are still high (#{pg_connections[:percentage]}%) after cleanup."
          # Don't restart PostgreSQL automatically as it can cause issues
          # system("brew services restart postgresql@14")
        end
      end

      # Clean up stale processes
      cleanup_stale_processes

      # Process any ready jobs
      process_ready_jobs

      # Clean up orphaned executions
      cleanup_orphaned_executions

      # Start SolidQueue processes if needed
      if should_start_processes?
        start_processes
      end

      Rails.logger.info "SolidQueue initialization complete!"
    end

    def cleanup_stale_processes
      Rails.logger.info "Cleaning up stale SolidQueue processes..."

      # Clean up processes on this host
      SolidQueue::Process.where(hostname: Socket.gethostname).find_each do |process|
        Rails.logger.info "Deregistering stale process: #{process.name} (#{process.id})"
        process.destroy
      end

      # Clean up processes that haven't had a heartbeat in 5 minutes
      SolidQueue::Process.where("last_heartbeat_at < ?", 5.minutes.ago).find_each do |process|
        Rails.logger.info "Deregistering stale process: #{process.name} (#{process.id})"
        process.destroy
      end

      # Clean up orphaned claimed executions
      SolidQueue::ClaimedExecution.joins("LEFT JOIN solid_queue_processes ON solid_queue_processes.id = process_id")
                                 .where("solid_queue_processes.id IS NULL")
                                 .delete_all

      # Clean up expired blocked executions
      SolidQueue::BlockedExecution.where("expires_at < ?", Time.current).delete_all
    end

    def process_ready_jobs
      Rails.logger.info "Processing ready jobs..."

      # Process ready jobs
      SolidQueue::ReadyExecution.find_each do |execution|
        begin
          job = execution.job
          Rails.logger.info "Processing job: #{job.id} (#{job.class_name})"

          # Try to execute the job directly
          serialized_job = JSON.parse(job.arguments) rescue nil
          if serialized_job && job.active_job_id.present?
            begin
              job.class_name.constantize.perform_now(*serialized_job['arguments'])
              job.update!(finished_at: Time.current, failed_at: nil)
              execution.destroy
              Rails.logger.info "Successfully processed job: #{job.id}"
            rescue => e
              Rails.logger.error "Error processing job #{job.id}: #{e.message}"

              # Create failed execution
              SolidQueue::FailedExecution.create!(
                job_id: job.id,
                error: "#{e.class}: #{e.message}\n#{e.backtrace.join('\n')}"
              )
              job.update!(finished_at: Time.current, failed_at: Time.current)
              execution.destroy
            end
          else
            Rails.logger.warn "Could not parse job arguments for job: #{job.id}"
            job.update!(finished_at: Time.current, failed_at: Time.current)
            SolidQueue::FailedExecution.create!(
              job_id: job.id,
              error: "Could not parse job arguments"
            )
            execution.destroy
          end
        rescue => e
          Rails.logger.error "Error processing execution #{execution.id}: #{e.message}"
        end
      end
    end

    def cleanup_orphaned_executions
      Rails.logger.info "Cleaning up orphaned executions..."

      # Clean up orphaned claimed executions
      orphaned_claimed_executions = SolidQueue::ClaimedExecution.joins("LEFT JOIN solid_queue_processes ON solid_queue_processes.id = process_id")
                                                              .where("solid_queue_processes.id IS NULL")

      if orphaned_claimed_executions.any?
        Rails.logger.info "Cleaning up #{orphaned_claimed_executions.count} orphaned claimed executions"
        orphaned_claimed_executions.destroy_all
      end

      # Clean up expired blocked executions
      expired_blocked_executions = SolidQueue::BlockedExecution.where("expires_at < ?", Time.current)

      if expired_blocked_executions.any?
        Rails.logger.info "Cleaning up #{expired_blocked_executions.count} expired blocked executions"
        expired_blocked_executions.destroy_all
      end
    end

    def should_start_processes?
      # Check if there are any active processes
      active_processes = SolidQueue::Process.where(hostname: Socket.gethostname)
                                          .where("last_heartbeat_at > ?", 5.minutes.ago)
                                          .exists?

      # Only start processes in development mode and if there are no active processes
      Rails.env.development? && !active_processes
    end

    def start_processes
      Rails.logger.info "Starting SolidQueue processes..."

      # Check disk space
      disk_space = check_disk_space
      if disk_space && disk_space[:warning]
        Rails.logger.warn "Disk space is critically low (#{disk_space[:percentage]}% used). This may cause issues with SolidQueue."
        # Clean up log files
        system("#{Rails.root}/bin/clean_logs.sh")

        # Check disk space again
        disk_space = check_disk_space
        if disk_space && disk_space[:warning]
          Rails.logger.error "Disk space is still critically low (#{disk_space[:percentage]}% used) after cleanup. Please free up disk space manually."
          return false
        end
      end

      # Check PostgreSQL connections
      pg_connections = PostgresConnectionManager.connection_status
      if pg_connections[:warning]
        Rails.logger.warn "PostgreSQL connections are high (#{pg_connections[:percentage]}%). This may cause issues with SolidQueue."
        PostgresConnectionManager.cleanup_connections

        # Check connections again
        pg_connections = PostgresConnectionManager.connection_status
        if pg_connections[:warning]
          Rails.logger.error "PostgreSQL connections are still high (#{pg_connections[:percentage]}%) after cleanup. Restarting PostgreSQL..."
          system("brew services restart postgresql@14")
          sleep 5
        end
      end

      # Start SolidQueue processes
      system("#{Rails.root}/bin/start_solid_queue")

      true
    end

    def stop_processes
      Rails.logger.info "Stopping SolidQueue processes..."

      # Kill any running SolidQueue processes
      system("pkill -f solid_queue_monitor.rb")

      # Clean up processes in the database
      SolidQueue::Process.where(hostname: Socket.gethostname).destroy_all

      true
    end

    def restart_processes
      stop_processes
      sleep 2
      start_processes
    end

    def check_disk_space
      begin
        # Check disk space for the Rails root directory
        df_output = `df -k #{Rails.root}`.split("\n")[1]
        if df_output
          # Parse the output
          parts = df_output.split
          capacity = parts[4].to_i rescue 0
          total_kb = parts[1].to_i rescue 0
          used_kb = parts[2].to_i rescue 0
          available_kb = parts[3].to_i rescue 0

          # Convert to human-readable format
          total = (total_kb / 1024.0 / 1024.0).round(2)  # GB
          used = (used_kb / 1024.0 / 1024.0).round(2)    # GB
          available = (available_kb / 1024.0 / 1024.0).round(2)  # GB

          warning = capacity > 90
          critical = capacity > 95

          {
            percentage: capacity,
            warning: warning,
            critical: critical,
            total_gb: total,
            used_gb: used,
            available_gb: available,
            mount_point: parts[5],
            message: if critical
                      "Disk space is critically low (#{capacity}% used). This may cause serious issues with the application."
                    elsif warning
                      "Disk space is running low (#{capacity}% used). This may cause issues with the application."
                    else
                      nil
                    end
          }
        else
          nil
        end
      rescue => e
        Rails.logger.error "Error checking disk space: #{e.message}"
        nil
      end
    end

    def status
      begin
        # Check for active processes
        workers = SolidQueue::Process.where(kind: ["Worker", "DirectWorker"])
                                   .where("last_heartbeat_at > ?", 5.minutes.ago)
                                   .count

        dispatcher = SolidQueue::Process.where(kind: "Dispatcher")
                                      .where("last_heartbeat_at > ?", 5.minutes.ago)
                                      .exists?

        # Get queue information
        queues = SolidQueue::Queue.all.map do |queue|
          {
            name: queue.name,
            paused: queue.paused?,
            jobs_pending: SolidQueue::Job.where(queue_name: queue.name, finished_at: nil).count
          }
        end

        # Get job statistics
        completed_jobs = SolidQueue::Job.where.not(finished_at: nil).count
        failed_jobs = SolidQueue::Failed.count
        pending_jobs = SolidQueue::Job.where(finished_at: nil).count

        # Get recent jobs
        recent_jobs = SolidQueue::Job.order(created_at: :desc).limit(5).map do |job|
          {
            id: job.id,
            class_name: job.class_name,
            queue_name: job.queue_name,
            created_at: job.created_at,
            finished_at: job.finished_at,
            status: job.finished_at.present? ? 'completed' : 'pending'
          }
        end

        # Check disk space
        disk_space = check_disk_space

        # Check PostgreSQL connections
        pg_connections = PostgresConnectionManager.connection_status rescue nil

        result = {
          status: (workers > 0 && dispatcher) ? "ok" : "warning",
          active_workers: workers,
          dispatcher_running: dispatcher,
          queues: queues,
          jobs: {
            completed: completed_jobs,
            failed: failed_jobs,
            pending: pending_jobs,
            recent: recent_jobs
          },
          auto_start: Rails.env.development?
        }

        # Add disk space info if available
        result[:disk_space] = disk_space if disk_space

        # Add PostgreSQL connection info if available
        result[:pg_connections] = pg_connections if pg_connections

        # Add system info
        result[:system] = {
          hostname: Socket.gethostname,
          pid: Process.pid,
          uptime: (Time.now - Rails.application.initialized_at).to_i,
          ruby_version: RUBY_VERSION,
          rails_version: Rails.version
        }

        result
      rescue => e
        Rails.logger.error "Error getting SolidQueue status: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        {
          status: "error",
          error: e.message,
          error_backtrace: Rails.env.development? ? e.backtrace.first(5) : nil
        }
      end
    end
  end
end
