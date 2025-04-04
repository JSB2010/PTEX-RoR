#!/usr/bin/env ruby
# Script to monitor SolidQueue

require_relative '../config/environment'

# Function to get SolidQueue information
def get_solid_queue_info
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
  
  {
    status: (workers > 0 && dispatcher) ? "ok" : "warning",
    active_workers: workers,
    dispatcher_running: dispatcher,
    queues: queues,
    jobs: {
      completed: completed_jobs,
      failed: failed_jobs,
      pending: pending_jobs,
      recent: recent_jobs
    }
  }
end

# Function to restart SolidQueue
def restart_solid_queue
  # Kill any existing SolidQueue processes
  system("pkill -f solid_queue_monitor.rb")
  sleep 2
  
  # Clean up processes in the database
  SolidQueue::Process.where(hostname: Socket.gethostname).destroy_all
  
  # Start SolidQueue processes
  system("#{Rails.root}/bin/start_solid_queue")
  
  true
end

# Parse command line arguments
require 'optparse'

options = {
  interval: 5,
  count: nil,
  restart: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  
  opts.on("-i", "--interval SECONDS", Integer, "Interval between checks (default: 5)") do |i|
    options[:interval] = i
  end
  
  opts.on("-c", "--count COUNT", Integer, "Number of checks to perform (default: infinite)") do |c|
    options[:count] = c
  end
  
  opts.on("-r", "--restart", "Restart SolidQueue if it's not running properly") do
    options[:restart] = true
  end
  
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

puts "Monitoring SolidQueue..."
puts "Press Ctrl+C to stop"
puts

count = 0
loop do
  count += 1
  break if options[:count] && count > options[:count]
  
  info = get_solid_queue_info
  
  puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}: Status: #{info[:status]}"
  puts "  Active workers: #{info[:active_workers]}, Dispatcher running: #{info[:dispatcher_running]}"
  puts "  Jobs: #{info[:jobs][:pending]} pending, #{info[:jobs][:completed]} completed, #{info[:jobs][:failed]} failed"
  
  if info[:status] == "warning" && options[:restart]
    puts "  WARNING: SolidQueue is not running properly. Restarting..."
    restart_solid_queue
  end
  
  sleep options[:interval]
end
