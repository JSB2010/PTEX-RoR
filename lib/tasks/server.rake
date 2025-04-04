# lib/tasks/server.rake
namespace :server do
  desc "Start all services (web, PostgreSQL, Redis, SolidQueue)"
  task start: :environment do
    # Check for dependent services first
    check_dependencies
    
    # Create a Procfile.dev if it doesn't exist
    procfile_dev_path = Rails.root.join('Procfile.dev')
    
    unless File.exist?(procfile_dev_path)
      File.open(procfile_dev_path, 'w') do |f|
        f.puts "web: bundle exec puma -C config/puma.rb"
        f.puts "solidqueue: bin/direct_solid_queue_worker"
      end
      puts "Created Procfile.dev with web and background job configurations"
    end
    
    # Check if Foreman is installed
    unless system("which foreman > /dev/null 2>&1")
      puts "Foreman is not installed. Installing it now..."
      system("gem install foreman")
    end
    
    # Launch all services with Foreman
    port = ENV['PORT'] || '3000'
    puts "\n🚀 Starting all services on port #{port}..."
    puts "📝 Web server (Puma)"
    puts "🧩 SolidQueue background jobs"
    puts "🔄 Redis cache"
    puts "🗄️ PostgreSQL database"
    puts "\n👉 Use Ctrl+C to gracefully stop all services\n"
    
    # Use exec to replace the current process, making Ctrl+C work correctly for all processes
    exec({ "PORT" => port.to_s, "RAILS_ENV" => Rails.env }, "foreman start -f #{procfile_dev_path}")
  end
  
  desc "Stop all services"
  task stop: :environment do
    puts "Stopping all services..."
    
    # Stop SolidQueue
    system("bin/solid_queue stop")
    
    # Stop Puma (if running)
    puma_pid_file = Rails.root.join('tmp', 'pids', 'server.pid')
    if File.exist?(puma_pid_file)
      pid = File.read(puma_pid_file).strip
      if pid.present?
        puts "Stopping Rails server (Puma) with PID #{pid}..."
        system("kill -TERM #{pid}")
      end
      File.delete(puma_pid_file) if File.exist?(puma_pid_file)
    end
    
    puts "All services stopped successfully"
  end
  
  desc "Restart all services"
  task restart: ["server:stop", "server:start"]
  
  # Helper method to check dependencies
  def check_dependencies
    puts "Checking dependencies..."
    
    # Check PostgreSQL
    pg_status = system("pg_isready > /dev/null 2>&1")
    puts pg_status ? "✅ PostgreSQL is running" : "⚠️ PostgreSQL may not be running"
    
    # Check Redis
    redis_running = system("redis-cli ping > /dev/null 2>&1")
    puts redis_running ? "✅ Redis is running" : "⚠️ Redis may not be running"
    
    # Check if SolidQueue is already running
    solid_queue_running = false
    solid_queue_pid_file = Rails.root.join('tmp', 'pids', 'solid_queue.pid')
    if File.exist?(solid_queue_pid_file)
      pid = File.read(solid_queue_pid_file).strip
      if pid.present? && system("ps -p #{pid} > /dev/null 2>&1")
        solid_queue_running = true
      end
    end
    puts solid_queue_running ? "✅ SolidQueue is already running" : "ℹ️ SolidQueue will be started"
  end
end

# Override the default Rails server command
task server: "server:start"
task s: "server:start"