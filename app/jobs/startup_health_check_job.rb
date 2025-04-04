class StartupHealthCheckJob < ApplicationJob
  queue_as :default

  def perform(initial: false)
    results = StartupCheckService.run
    
    if results[:server_status][:status] == 'success' && all_services_healthy?(results[:service_checks])
      log_success(results)
    else
      log_failures(results)
      schedule_retry if initial
    end
  end

  private

  def all_services_healthy?(service_checks)
    service_checks.values.all? { |check| check[:status] == 'success' || check[:status] == 'warning' }
  end

  def log_success(results)
    puts "\n✅ Health check passed"
    puts "Response time: #{results[:server_status][:response_time]}s"
    
    # Log any warnings
    results[:service_checks].each do |service, check|
      if check[:status] == 'warning'
        puts "⚠️  #{service.to_s.titleize}: #{check[:message]}"
      end
    end
    
    # Show database stats if available
    if results[:database_checks] && results[:database_checks][:status] == 'success'
      db = results[:database_checks]
      puts "\nDatabase connection pool: #{db[:pool][:active]}/#{db[:pool][:size]} connections active"
      
      if db[:tables].present?
        puts "\nTable statistics:"
        db[:tables].each do |table, stats|
          puts "- #{table}: #{stats[:rows]} rows (#{stats[:size]})"
        end
      end
    end
  end

  def log_failures(results)
    puts "\n❌ Health check failed:"
    
    if results[:server_status][:status] == 'error'
      puts "- Server: #{results[:server_status][:message]}"
    end
    
    results[:service_checks].each do |service, check|
      if check[:status] == 'error'
        puts "- #{service.to_s.titleize}: #{check[:message]}"
      end
    end
    
    if results[:database_checks] && results[:database_checks][:status] == 'error'
      puts "- Database details: #{results[:database_checks][:message]}"
    end
  end

  def schedule_retry
    self.class.set(wait: 10.seconds).perform_later(initial: true)
  end
end