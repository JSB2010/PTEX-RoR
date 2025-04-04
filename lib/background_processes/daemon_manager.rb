require 'socket'
require 'fileutils'

module BackgroundProcesses
  class DaemonManager
    SOCKET_PATH = Rails.root.join('tmp/sockets/background_processes.sock').to_s

    class << self
      def start_services
        return if Rails.env.test? || ENV['SKIP_SERVICES']
        ensure_socket_directory
        remove_stale_socket

        @pid = start_foreman
        at_exit { stop_services }
      end

      private

      def ensure_socket_directory
        FileUtils.mkdir_p(File.dirname(SOCKET_PATH))
      end

      def remove_stale_socket
        File.unlink(SOCKET_PATH) if File.exist?(SOCKET_PATH)
      end

      def start_foreman
        command = "bundle exec foreman start -f Procfile"
        log_file = Rails.root.join("log/foreman.log").to_s
        
        pid = Process.spawn(
          { "RAILS_ENV" => Rails.env },
          command,
          out: log_file,
          err: log_file,
          pgroup: true
        )
        Process.detach(pid)
        pid
      end

      def stop_services
        if @pid
          begin
            Process.kill('-TERM', @pid)
          rescue Errno::ESRCH
            # Process already gone
          end
        end
        
        # Clean up any remaining processes
        SolidQueue::Process.where(hostname: Socket.gethostname).find_each(&:deregister)
      end
    end
  end
end