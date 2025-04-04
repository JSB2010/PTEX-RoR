# frozen_string_literal: true

module SolidQueue
  class Dispatcher
    include SolidQueue::Processes::Registrable
    include SolidQueue::Processes::Runnable
    
    attr_reader :polling_interval, :batch_size, :logger, :name
    
    def initialize(options = {})
      @polling_interval = options[:polling_interval].to_f
      @batch_size = options[:batch_size].to_i
      @name = options[:name] || "dispatcher"
      @logger = options[:logger] || Rails.logger
      @running = true
      @error_counts = Concurrent::Hash.new(0)
      @last_error_reset = Time.current
    end
    
    def poll(batch = nil)
      begin
        results = []
        
        if @running
          results.concat(dispatch_scheduled_jobs)
          results.concat(dispatch_recurring_jobs)
          results.concat(cleanup_stale_jobs)
        end
        
        # Improved sleep handling
        batch_empty = batch.nil? || (batch.is_a?(Array) ? batch.empty? : batch.zero?)
        sleep_duration = results.empty? && batch_empty ? @polling_interval : 0
        sleep(sleep_duration) if sleep_duration > 0
        
        results
      rescue => e
        handle_error(e)
        []
      end
    end
    
    def start
      @logger.info "Starting SolidQueue dispatcher"
      while @running
        begin
          poll
        rescue => e
          handle_error(e)
        end
      end
    end
    
    def stop
      @logger.info "Stopping SolidQueue dispatcher"
      @running = false
    end
    
    private
    
    def dispatch_scheduled_jobs
      SolidQueue::Job.transaction do
        jobs = SolidQueue::ScheduledExecution
          .joins(:job)
          .where("scheduled_at <= ?", Time.current)
          .limit(@batch_size)
          .lock("FOR UPDATE SKIP LOCKED")
          .to_a
        
        moved_jobs = []
        jobs.each do |execution|
          begin
           
