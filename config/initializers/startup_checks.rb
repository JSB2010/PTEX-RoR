# Require Net::HTTP for health checks
require 'net/http'
require 'json'

# Perform health checks during startup in development and production
if Rails.env.development? || Rails.env.production?
  Rails.application.config.after_initialize do
    if defined?(Rails::Server)
      puts "\nRunning startup health check..."
      port = ENV.fetch('PORT', 3003)  # Default to 3003 for this project
      uri = URI.parse("http://localhost:#{port}/health")
      
      Thread.new do
        begin
          sleep 5 # Give the server time to start
          response = Net::HTTP.get_response(uri)
          
          if response.code == "200"
            health_data = JSON.parse(response.body)
            puts "✅ Health check passed"
            puts "Database connections: #{health_data["database"]["active_connections"]}/#{health_data["database"]["pool_size"]}"
            puts "Redis status: #{health_data["redis"]["connected"] ? "Connected" : "Disconnected"}"
            puts "Job system status: #{health_data["job_system"]["status"]}"
          else
            puts "❌ Health check failed with status #{response.code}"
          end
        rescue => e
          puts "❌ Health check failed: #{e.message}"
        end
      end
    end
  end
end

# Hook into Rails console startup for manual testing
if Rails.env.development? && defined?(IRB)
  puts "\nℹ️  You can run health checks manually with:"
  puts "  Net::HTTP.get_response(URI.parse('http://localhost:3000/health'))"
end