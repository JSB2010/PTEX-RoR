namespace :health do
  desc 'Run application health checks'
  task check: :environment do
    require 'terminal-table'
    require 'rainbow'

    puts Rainbow("\nRunning application health checks...").bright

    results = StartupCheckService.run
    
    # Server Status Table
    server = results[:server_status]
    puts "\n#{Rainbow('Server Status').underline}"
    server_table = Terminal::Table.new do |t|
      t.add_row ['Status', colorize_status(server[:status], server[:status])]
      t.add_row ['Message', server[:message]]
      t.add_row ['Response Time', "#{server[:response_time]}s"] if server[:response_time]
    end
    puts server_table

    # Services Table
    if results[:service_checks]
      puts "\n#{Rainbow('Critical Services').underline}"
      services_table = Terminal::Table.new do |t|
        t.headings = ['Service', 'Status', 'Message']
        results[:service_checks].each do |service, check|
          t.add_row [
            service.to_s.capitalize,
            colorize_status(check[:status], check[:status]),
            check[:message]
          ]
        end
      end
      puts services_table
    end

    # Database Health
    if results[:database_checks]
      puts "\n#{Rainbow('Database Health').underline}"
      db = results[:database_checks]
      if db[:status] == 'success'
        db_table = Terminal::Table.new do |t|
          t.add_row ['Pool Size', "#{db[:pool][:active]}/#{db[:pool][:size]} active"]
          t.add_row ['Queue Status', "#{db[:pool][:waiting]} waiting"]
          if db[:tables]
            db[:tables].each do |table, stats|
              t.add_row [table, "#{stats[:rows]} rows (#{stats[:size]})"]
            end
          end
        end
        puts db_table
      else
        puts Rainbow("Error: #{db[:message]}").red
      end
    end

    # Background Jobs
    if results[:job_checks]
      puts "\n#{Rainbow('Background Jobs').underline}"
      jobs_table = Terminal::Table.new do |t|
        t.headings = ['Check', 'Status', 'Details']
        results[:job_checks].each do |check_type, status|
          t.add_row [
            check_type.to_s.titleize,
            colorize_status(status[:status], status[:status]),
            status[:message]
          ]
        end
      end
      puts jobs_table
    end

    # Log Issues
    if results[:log_checks]&.any?
      puts "\n#{Rainbow('Log Issues').underline}"
      results[:log_checks].each do |type, errors|
        puts "\n#{Rainbow(type.to_s.capitalize + ' Log').yellow} (#{errors.size} issues)"
        errors.take(5).each do |error|
          puts Rainbow("  • #{error}").red
        end
        if errors.size > 5
          puts Rainbow("  ... and #{errors.size - 5} more").yellow
        end
      end
    end

    # Final Status
    success = results.values.all? do |check|
      check.is_a?(Hash) ? check[:status] == 'success' : true
    end

    puts "\n#{Rainbow('Final Status').underline}"
    if success
      puts Rainbow("✅ All checks passed").green
    else
      puts Rainbow("❌ Some checks failed").red
    end
  end

  private

  def colorize_status(status, text)
    case status
    when 'success'
      Rainbow(text).green
    when 'warning'
      Rainbow(text).yellow
    else
      Rainbow(text).red
    end
  end
end