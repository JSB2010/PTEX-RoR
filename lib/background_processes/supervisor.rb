require 'fileutils'

module BackgroundProcesses
  class Supervisor
    HEARTBEAT_INTERVAL = 30  # seconds
    RESTART_DELAY = 5        # seconds
    PID_DIR = Rails.root.join('tmp', 'pids')

    def self.start
      new.start
    end

    def initialize
      @processes = []
      @shutdown = false
      @mutex = Mutex.new
    end

    def start
      trap_signals
      start_processes
      monitor_loop
    end

    private

    def trap_signals
      %w[TERM INT].each do |signal|
        Signal.trap(signal) { shutdown }
      end
    end

    def start_processes
      config = SolidQueue::Configuration.load
      worker_count = config['concurrency'] || 5

      worker_count.times do |i|
        start_worker(i)
      end

      start_dispatcher
    end

    def start_worker(index)
      spawn_process("Worker-#{index}") do
        SolidQueue::Worker.new.start
      end
    end

    def start_dispatcher
      spawn_process("Dispatcher") do
        SolidQueue::Dispatcher.new.start
      end
    end

    def spawn_process(name)
      pid = fork do
        $0 = "solid_queue: #{name}"
        yield
      end

      @mutex.synchronize do
        @processes << { name: name, pid: pid, started_at: Time.current }
      end

      Process.detach(pid)
    end

    def monitor_loop
      until @shutdown
        check_processes
        sleep 5
      end

      shutdown_processes
    end

    def check_processes
      @mutex.synchronize do
        @processes.each do |process|
          unless process_alive?(process[:pid])
            JobLogger.error("Process died, restarting", 
              process_name: process[:name], 
              pid: process[:pid]
            )
            restart_process(process)
          end
        end
      end
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end

    def restart_process(process)
      @processes.delete(process)
      if process[:name].start_with?("Worker")
        index = process[:name].split("-").last
        start_worker(index)
      elsif process[:name] == "Dispatcher"
        start_dispatcher
      end
    end

    def shutdown
      @shutdown = true
    end

    def shutdown_processes
      @mutex.synchronize do
        @processes.each do |process|
          begin
            Process.kill("TERM", process[:pid])
          rescue Errno::ESRCH
            # Process already gone
          end
        end
      end

      wait_for_processes
    end

    def wait_for_processes
      30.times do
        break if @processes.none? { |p| process_alive?(p[:pid]) }
        sleep 1
      end

      @processes.each do |process|
        if process_alive?(process[:pid])
          Process.kill("KILL", process[:pid]) rescue nil
        end
      end
    end
  end
end