# frozen_string_literal: true

module SolidQueueHelper
  class << self
    def running?
      return false unless defined?(SolidQueue::Process)
      
      # Check if supervisor process is running
      supervisor = SolidQueue::Process.where(kind: "Supervisor")
                                     .where("last_heartbeat_at > ?", 2.minutes.ago)
                                     .exists?
                                     
      # Also check for any active workers
      workers = SolidQueue::Process.where(kind: ["Worker", "DirectWorker"])
                                  .where("last_heartbeat_at > ?", 2.minutes.ago)
                                  .exists?
                                  
      supervisor && workers
    end
    
    def start_supervisor
      return if running?
      
      if Rails.env.development?
        Rails.logger.info "Starting SolidQueue supervisor..."
        
        # In development, try to start the processes
        begin
          pid = spawn("bin/start_solid_queue", out: "log/solid_queue.log", err: "log/solid_queue.log")
          Process.detach(pid)
          Rails.logger.info "SolidQueue supervisor started with PID: #{pid}"
          true
        rescue => e
          Rails.logger.error "Failed to start SolidQueue supervisor: #{e.message}"
          false
        end
      else
        Rails.logger.warn "Cannot start SolidQueue supervisor outside of development"
        false
      end
    end
    
    def stop_supervisor
      return unless Rails.env.development?
      
      Rails.logger.info "Stopping SolidQueue supervisor..."
      begin
        system("pkill -f 'solid_queue:supervisor'")
        true
      rescue => e
        Rails.logger.error "Failed to stop SolidQueue supervisor: #{e.message}"
        false
      end
    end
    
    def worker_status
      return {} unless defined?(SolidQueue::Process)
      
      workers = SolidQueue::Process.where(kind: ["Worker", "DirectWorker"])
                                   .where("last_heartbeat_at > ?", 5.minutes.ago)
      
      {
        count: workers.count,
        active: workers.any?,
        last_heartbeat: workers.order(last_heartbeat_at: :desc).first&.last_heartbeat_at,
        process_ids: workers.pluck(:pid).compact
      }
    end
    
    def job_backlog
      return {} unless defined?(SolidQueue::Job)
      
      {
        pending: SolidQueue::Job.where(finished_at: nil).count,
        ready: SolidQueue::ReadyExecution.count,
        scheduled: SolidQueue::ScheduledExecution.count,
        failed: SolidQueue::FailedExecution.count
      }
    end
  end

  # Check if SolidQueue is properly configured and running
  def self.check_solid_queue_health
    {
      dispatcher_process: check_dispatcher_process,
      worker_processes: check_worker_processes,
      queued_jobs: check_queued_jobs,
      failed_jobs: check_failed_jobs
    }
  end

  # Check if the dispatcher process is running
  def self.check_dispatcher_process
    pid_file = Rails.root.join('tmp', 'pids', 'solid_queue_dispatcher.pid')
    
    if File.exist?(pid_file)
      pid = File.read(pid_file).strip.to_i
      return { status: 'running', pid: pid } if process_running?(pid)
    end
    
    { status: 'not_running' }
  end

  # Check if worker processes are running
  def self.check_worker_processes
    pid_file = Rails.root.join('tmp', 'pids', 'solid_queue_worker.pid')
    
    if File.exist?(pid_file)
      pid = File.read(pid_file).strip.to_i
      return { status: 'running', pid: pid } if process_running?(pid)
    end
    
    { status: 'not_running' }
  end

  # Check for queued jobs
  def self.check_queued_jobs
    require 'solid_queue/job'
    job_count = SolidQueue::Job.where(finished_at: nil).count
    { count: job_count }
  end

  # Check for failed jobs
  def self.check_failed_jobs
    require 'solid_queue/job'
    failed_count = SolidQueue::Job.where.not(error_object: nil).count
    { count: failed_count }
  end

  private

  # Check if a process with given PID is running
  def self.process_running?(pid)
    begin
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end
  end
end