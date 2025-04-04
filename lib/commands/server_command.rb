#!/usr/bin/env ruby
require 'fileutils'
require "rails/command"
require "rails/commands/server/server_command"

module Rails
  module Command
    class ServerCommand < Base
      def perform
        verify_db_and_migrations
        
        # Clean up any stale processes
        SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)
        
        # Start the Rails server with Solid Queue
        @server_pid = fork do
          ENV["SOLID_QUEUE_ENABLED"] = "true"
          Rails::Server.new.start
        end

        # Start Solid Queue worker
        @worker_pid = fork do
          process = SolidQueue::Process.create!(
            kind: "Worker",
            name: "worker-#{SecureRandom.hex(6)}",
            hostname: Socket.gethostname,
            pid: Process.pid
          )

          SolidQueue::Worker.new(
            name: process.name, 
            logger: Rails.logger
          ).start
        end

        # Start Solid Queue dispatcher
        @dispatcher_pid = fork do
          process = SolidQueue::Process.create!(
            kind: "Dispatcher",
            name: "dispatcher-#{SecureRandom.hex(6)}",
            hostname: Socket.gethostname,
            pid: Process.pid
          )

          SolidQueue::Dispatcher.new(
            name: process.name, 
            logger: Rails.logger
          ).start
        end

        # Handle process cleanup
        at_exit do
          Process.kill("TERM", @server_pid) rescue nil
          Process.kill("TERM", @worker_pid) rescue nil
          Process.kill("TERM", @dispatcher_pid) rescue nil
          Process.wait(@server_pid) rescue nil
          Process.wait(@worker_pid) rescue nil
          Process.wait(@dispatcher_pid) rescue nil
        end

        # Wait for processes
        Process.waitall
      end

      private

      def verify_db_and_migrations
        # Ensure database exists
        unless ActiveRecord::Base.connection.table_exists?('schema_migrations')
          system('bin/rails db:create')
          system('bin/rails db:schema:load')
          system('bin/rails db:seed')
        end

        # Check for pending migrations
        if ActiveRecord::Base.connection.migration_context.needs_migration?
          system('bin/rails db:migrate')
        end
      rescue ActiveRecord::NoDatabaseError
        system('bin/rails db:create')
        system('bin/rails db:schema:load')
        system('bin/rails db:seed')
        retry
      end

      def server_options
        Rails::Server::Options.new.parse!(args)
      end

      def setup_dev_caching(options)
        if options[:environment] == "development"
          Rails::DevCaching.enable_by_file
        end
      end

      def after_setup_dev_caching(options)
        if options[:environment] == "development" && !options[:daemon]
          trap(:INT) { exit }
          create_tmp_directories
        end
      end

      def create_tmp_directories
        %w(cache pids sockets).each do |dir_to_make|
          FileUtils.mkdir_p(Rails.root.join('tmp', dir_to_make))
        end
      end
    end
  end
end