require "rails/command"
require "rails/commands/server/server_command"

module Rails
  module Command
    class UnifiedServerCommand < ServerCommand
      def perform
        validate_database
        trap_signals
        start_services
        super
      end

      private

      def validate_database
        return if ENV['SKIP_DB_CHECK']

        unless ActiveRecord::Base.connection.table_exists?('schema_migrations')
          system('bin/rails db:create')
          system('bin/rails db:schema:load')
          system('bin/rails db:seed')
        end

        if ActiveRecord::Base.connection.migration_context.needs_migration?
          system('bin/rails db:migrate')
        end
      rescue ActiveRecord::NoDatabaseError
        system('bin/rails db:create')
        system('bin/rails db:schema:load')
        system('bin/rails db:seed')
        retry
      end

      def trap_signals
        trap(:INT) { exit_gracefully }
        trap(:TERM) { exit_gracefully }
      end

      def start_services
        @worker_thread = Thread.new do
          worker_config = {
            processes: [{
              name: "worker-#{SecureRandom.hex(6)}",
              kind: "Worker",
              polling_interval: ENV.fetch("SOLID_QUEUE_POLLING_INTERVAL", "0.1").to_f,
              batch_size: ENV.fetch("SOLID_QUEUE_BATCH_SIZE", "100").to_i,
              threads: ENV.fetch("SOLID_QUEUE_CONCURRENCY", "5").to_i,
              queues: ENV.fetch("SOLID_QUEUE_QUEUES", "default,mailers,active_storage,maintenance").split(",")
            }]
          }
          SolidQueue::Supervisor.new(worker_config).start
        end

        @dispatcher_thread = Thread.new do
          dispatcher_config = {
            processes: [{
              name: "dispatcher-#{SecureRandom.hex(6)}",
              kind: "Dispatcher",
              polling_interval: ENV.fetch("SOLID_QUEUE_POLLING_INTERVAL", "0.1").to_f,
              batch_size: ENV.fetch("SOLID_QUEUE_BATCH_SIZE", "100").to_i
            }]
          }
          SolidQueue::Supervisor.new(dispatcher_config).start
        end
      end

      def exit_gracefully
        SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)
        [@worker_thread, @dispatcher_thread].each { |t| t&.exit }
        exit
      end
    end
  end
end