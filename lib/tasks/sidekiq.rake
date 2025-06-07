require 'sidekiq/api'

namespace :sidekiq do
  desc "Start Sidekiq processes"
  task start: :environment do
    puts "Starting Sidekiq..."
    exec("bundle exec sidekiq")
  end

  desc "Stop Sidekiq processes"
  task stop: :environment do
    puts "Stopping Sidekiq..."
    system("pkill -f 'sidekiq' || true")
  end

  desc "Restart Sidekiq processes"
  task restart: [:stop, :start]

  desc "Check Sidekiq status"
  task status: :environment do
    puts "Sidekiq Status:"
    puts "Enqueued jobs: #{Sidekiq::Queue.new.size}"
    puts "Retry jobs: #{Sidekiq::RetrySet.new.size}"
    puts "Scheduled jobs: #{Sidekiq::ScheduledSet.new.size}"
    puts "Dead jobs: #{Sidekiq::DeadSet.new.size}"
  end
end
