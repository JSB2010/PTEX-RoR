#!/usr/bin/env ruby
# Script to fix job processing errors

require_relative '../config/environment'

puts "Fixing job processing errors..."

# Check for failed jobs
failed_jobs = SolidQueue::Failed.all
puts "Found #{failed_jobs.count} failed jobs"

# Check for stuck jobs
stuck_jobs = SolidQueue::Job.where(finished_at: nil).where('created_at < ?', 1.hour.ago)
puts "Found #{stuck_jobs.count} stuck jobs"

# Check for claimed executions
claimed_executions = SolidQueue::ClaimedExecution.all
puts "Found #{claimed_executions.count} claimed executions"

# Check for blocked executions
blocked_executions = SolidQueue::BlockedExecution.all
puts "Found #{blocked_executions.count} blocked executions"

# Check for ready executions
ready_executions = SolidQueue::ReadyExecution.all
puts "Found #{ready_executions.count} ready executions"

# Clean up stale processes
stale_processes = SolidQueue::Process.where('last_heartbeat_at < ?', 5.minutes.ago)
puts "Found #{stale_processes.count} stale processes"

if stale_processes.any?
  puts "Cleaning up stale processes..."
  stale_processes.each do |process|
    puts "Deregistering stale process: #{process.name} (#{process.id})"
    process.destroy
  end
end

# Clean up claimed executions with no process
orphaned_claimed_executions = SolidQueue::ClaimedExecution.joins('LEFT JOIN solid_queue_processes ON solid_queue_processes.id = process_id').where('solid_queue_processes.id IS NULL')
puts "Found #{orphaned_claimed_executions.count} orphaned claimed executions"

if orphaned_claimed_executions.any?
  puts "Cleaning up orphaned claimed executions..."
  orphaned_claimed_executions.destroy_all
end

# Clean up expired blocked executions
expired_blocked_executions = SolidQueue::BlockedExecution.where('expires_at < ?', Time.current)
puts "Found #{expired_blocked_executions.count} expired blocked executions"

if expired_blocked_executions.any?
  puts "Cleaning up expired blocked executions..."
  expired_blocked_executions.destroy_all
end

# Process ready jobs
if ready_executions.any?
  puts "Processing ready jobs..."
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
          puts e.backtrace.join("\n")
          
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
      end
    rescue => e
      puts "Error processing execution #{execution.id}: #{e.message}"
    end
  end
end

puts "Job processing fixes completed!"
