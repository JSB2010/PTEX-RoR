#!/usr/bin/env ruby
# Script to fix SolidQueue issues

require_relative '../config/environment'

puts "Fixing SolidQueue issues..."

# Check for database connection
begin
  ActiveRecord::Base.connection.execute("SELECT 1")
  puts "Database connection is working"
rescue => e
  puts "Database connection error: #{e.message}"
  exit 1
end

# Check for failed jobs
begin
  failed_jobs = SolidQueue::Failed.all
  puts "Found #{failed_jobs.count} failed jobs"

  if failed_jobs.any?
    puts "Cleaning up failed jobs..."
    failed_jobs.each do |failed|
      puts "Failed job: #{failed.job_id} - #{failed.error_message}"
      # You can retry or delete failed jobs here
    end
  end
rescue => e
  puts "Error checking failed jobs: #{e.message}"
end

# Check for stuck jobs
begin
  stuck_jobs = SolidQueue::Job.where(finished_at: nil).where('created_at < ?', 1.hour.ago)
  puts "Found #{stuck_jobs.count} stuck jobs"

  if stuck_jobs.any?
    puts "Cleaning up stuck jobs..."
    stuck_jobs.each do |job|
      puts "Stuck job: #{job.id} - #{job.class_name}"
      # Mark as finished to prevent further processing
      job.update!(finished_at: Time.current)
    end
  end
rescue => e
  puts "Error checking stuck jobs: #{e.message}"
end

# Check for claimed executions
begin
  claimed_executions = SolidQueue::ClaimedExecution.all
  puts "Found #{claimed_executions.count} claimed executions"

  # Clean up claimed executions with no process
  orphaned_claimed_executions = SolidQueue::ClaimedExecution.joins('LEFT JOIN solid_queue_processes ON solid_queue_processes.id = process_id').where('solid_queue_processes.id IS NULL')
  puts "Found #{orphaned_claimed_executions.count} orphaned claimed executions"

  if orphaned_claimed_executions.any?
    puts "Cleaning up orphaned claimed executions..."
    orphaned_claimed_executions.destroy_all
  end
rescue => e
  puts "Error checking claimed executions: #{e.message}"
end

# Check for blocked executions
begin
  blocked_executions = SolidQueue::BlockedExecution.all
  puts "Found #{blocked_executions.count} blocked executions"

  # Clean up expired blocked executions
  expired_blocked_executions = SolidQueue::BlockedExecution.where('expires_at < ?', Time.current)
  puts "Found #{expired_blocked_executions.count} expired blocked executions"

  if expired_blocked_executions.any?
    puts "Cleaning up expired blocked executions..."
    expired_blocked_executions.destroy_all
  end
rescue => e
  puts "Error checking blocked executions: #{e.message}"
end

# Check for ready executions
begin
  ready_executions = SolidQueue::ReadyExecution.all
  puts "Found #{ready_executions.count} ready executions"

  if ready_executions.any?
    puts "Processing ready executions..."
    ready_executions.each do |execution|
      begin
        job = execution.job
        puts "Processing job: #{job.id} (#{job.class_name})"
        
        # Try to execute the job directly
        serialized_job = JSON.parse(job.arguments) rescue nil
        if serialized_job && job.active_job_id.present?
          begin
            job.class_name.constantize.perform_now(*serialized_job['arguments'])
            job.update!(finished_at: Time.current)
            execution.destroy
            puts "Successfully processed job: #{job.id}"
          rescue => e
            puts "Error processing job #{job.id}: #{e.message}"
            
            # Move to failed queue
            SolidQueue::Failed.create!(
              job_id: job.id,
              error_message: e.message,
              error_backtrace: e.backtrace.join("\n")
            )
            job.update!(finished_at: Time.current)
            execution.destroy
          end
        else
          puts "Could not parse job arguments for job: #{job.id}"
          job.update!(finished_at: Time.current)
          execution.destroy
        end
      rescue => e
        puts "Error processing execution #{execution.id}: #{e.message}"
      end
    end
  end
rescue => e
  puts "Error checking ready executions: #{e.message}"
end

# Clean up stale processes
begin
  stale_processes = SolidQueue::Process.where('last_heartbeat_at < ?', 5.minutes.ago)
  puts "Found #{stale_processes.count} stale processes"

  if stale_processes.any?
    puts "Cleaning up stale processes..."
    stale_processes.each do |process|
      puts "Deregistering stale process: #{process.name} (#{process.id})"
      process.destroy
    end
  end
rescue => e
  puts "Error cleaning up stale processes: #{e.message}"
end

puts "SolidQueue fixes completed!"
