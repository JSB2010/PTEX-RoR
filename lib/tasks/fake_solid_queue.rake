namespace :fake_solid_queue do
  desc "Register fake SolidQueue processes in the database"
  task register: :environment do
    require 'socket'
    
    puts "Registering fake SolidQueue processes in the database..."
    
    # Clean up any existing processes from this host
    hostname = Socket.gethostname
    puts "Cleaning up existing SolidQueue processes for host: #{hostname}"
    SolidQueue::Process.where(hostname: hostname).destroy_all
    
    # Register a fake dispatcher process
    puts "Registering a fake dispatcher process"
    dispatcher = SolidQueue::Process.create!(
      kind: "Dispatcher",
      name: "dispatcher-#{hostname}",
      pid: Process.pid,
      hostname: hostname,
      last_heartbeat_at: Time.current,
      metadata: { polling_interval: 5 }.to_json
    )
    puts "Registered fake dispatcher process with ID: #{dispatcher.id}"
    
    # Register a fake worker process
    puts "Registering a fake worker process"
    worker = SolidQueue::Process.create!(
      kind: "Worker",
      name: "worker-#{hostname}",
      pid: Process.pid + 1,
      hostname: hostname,
      last_heartbeat_at: Time.current,
      metadata: { concurrency: 1, queues: ["default"] }.to_json
    )
    puts "Registered fake worker process with ID: #{worker.id}"
    
    puts "Fake SolidQueue processes registered."
  end
  
  desc "Update heartbeats for fake SolidQueue processes"
  task update_heartbeats: :environment do
    require 'socket'
    
    puts "Updating heartbeats for fake SolidQueue processes..."
    
    # Get all processes for this host
    hostname = Socket.gethostname
    processes = SolidQueue::Process.where(hostname: hostname)
    
    if processes.any?
      processes.each do |process|
        process.update!(last_heartbeat_at: Time.current)
        puts "Updated heartbeat for #{process.kind} process with ID: #{process.id}"
      end
    else
      puts "No processes found for host: #{hostname}"
    end
    
    puts "Heartbeats updated."
  end
end
