namespace :metrics do
  desc 'Schedule metrics cleanup job to run daily'
  task schedule_cleanup: :environment do
    return if ENV['SKIP_METRICS']
    CleanMetricsDataJob.perform_later if ActiveRecord::Base.connection.table_exists?('solid_queue_jobs')
  end

  desc 'Run metrics cleanup job immediately'
  task cleanup: :environment do
    return if ENV['SKIP_METRICS']
    CleanMetricsDataJob.perform_now if ActiveRecord::Base.connection.table_exists?('solid_queue_jobs')
  end

  desc 'Initialize metrics cleanup schedule'
  task init: :environment do
    return if ENV['SKIP_METRICS']
    return unless ActiveRecord::Base.connection.table_exists?('solid_queue_jobs')
    
    unless Rails.cache.exist?('metrics:cleanup:initialized')
      Rake::Task['metrics:schedule_cleanup'].invoke
      Rails.cache.write('metrics:cleanup:initialized', true, expires_in: 1.week)
    end
  end

  desc 'Export current metrics to Prometheus'
  task export: :environment do
    return if ENV['SKIP_METRICS']
    MetricsExporterService.collect_metrics
  end

  desc 'Reset all metrics in Prometheus'
  task reset: :environment do
    return if ENV['SKIP_METRICS']
    MetricsExporterService.reset_metrics
  end

  desc 'Show current metrics summary'
  task summary: :environment do
    return if ENV['SKIP_METRICS']
    
    require 'terminal-table'
    require 'rainbow'

    puts Rainbow("\nMetrics Summary").bright

    # Course Statistics
    Course.find_each do |course|
      today = Date.current.to_s
      
      hits = Rails.cache.read("metrics:course:#{course.id}:cache_hits:#{today}").to_i
      misses = Rails.cache.read("metrics:course:#{course.id}:cache_misses:#{today}").to_i
      avg_time = Rails.cache.read("metrics:course:#{course.id}:daily_avg_calculation_time:#{today}").to_f
      
      total = hits + misses
      hit_rate = total.zero? ? 0 : (hits.to_f / total * 100).round(1)
      
      puts "\n#{Rainbow(course.name).underline}"
      table = Terminal::Table.new do |t|
        t.add_row ['Cache Hit Rate', "#{hit_rate}% (#{hits}/#{total} hits)"]
        t.add_row ['Avg Calculation Time', "#{avg_time.round(2)}ms"]
      end
      puts table
    end
  end
end

# Hook into Rails startup - only after migrations
Rake::Task['db:migrate'].enhance do
  unless ENV['SKIP_METRICS']
    # Run after migrations complete
    Rake::Task['metrics:init'].invoke rescue nil
  end
end