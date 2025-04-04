require 'objspace'

# Enable memory profiling in production
ObjectSpace.trace_object_allocations_start if Rails.env.production?

# Configure memory monitoring
module MemoryMonitoring
  class << self
    def memory_stats
      {
        memory_usage_mb: `ps -o rss= -p #{Process.pid}`.to_i / 1024,
        gc_stats: GC.stat,
        object_counts: object_allocation_stats,
        object_space: collect_object_space_stats,
        retained_objects: collect_retained_objects
      }
    end

    def object_allocation_stats
      return {} unless Rails.env.production?

      {
        total_objects: ObjectSpace.count_objects[:TOTAL],
        heap_pages: GC.stat[:heap_allocated_pages],
        heap_slots: ObjectSpace.count_tdata_objects,
        generation_stats: collect_generation_stats
      }
    end

    def check_memory_threshold
      memory_usage = `ps -o rss= -p #{Process.pid}`.to_i / 1024
      threshold = ENV.fetch('MEMORY_THRESHOLD_MB', 1024).to_i

      if memory_usage > threshold
        stats = memory_stats
        Rails.logger.warn("High memory usage detected: #{stats.to_json}")
        
        if defined?(Sentry)
          Sentry.capture_message(
            "High memory usage detected",
            level: 'warning',
            extra: stats
          )
        end

        trigger_gc_if_needed(memory_usage, threshold)
      end
    end

    private

    def collect_object_space_stats
      return {} unless Rails.env.production?

      {
        strings: ObjectSpace.count_objects(current_gen: true)[:T_STRING],
        arrays: ObjectSpace.count_objects(current_gen: true)[:T_ARRAY],
        hashes: ObjectSpace.count_objects(current_gen: true)[:T_HASH],
        objects: ObjectSpace.count_objects(current_gen: true)[:T_OBJECT]
      }
    end

    def collect_retained_objects(limit = 100)
      return [] unless Rails.env.production?

      retained = Hash.new(0)
      ObjectSpace.each_object do |obj|
        if obj.respond_to?(:object_id) && !obj.frozen?
          location = ObjectSpace.allocation_sourcefile(obj)
          next unless location && location.include?(Rails.root.to_s)
          
          key = "#{location}:#{ObjectSpace.allocation_sourceline(obj)}"
          retained[key] += 1
        end
      end

      retained.sort_by { |_, count| -count }.first(limit).to_h
    end

    def collect_generation_stats
      {
        count: GC.stat[:count],
        major_gc_count: GC.stat[:major_gc_count],
        minor_gc_count: GC.stat[:minor_gc_count],
        total_promoted_objects: GC.stat[:total_promoted_objects],
        heap_allocatable_pages: GC.stat[:heap_allocatable_pages],
        heap_available_slots: GC.stat[:heap_available_slots],
        heap_live_slots: GC.stat[:heap_live_slots],
        remembered_wb_unprotected_objects: GC.stat[:remembered_wb_unprotected_objects]
      }
    end

    def trigger_gc_if_needed(current_usage, threshold)
      if current_usage > (threshold * 1.5)
        before_gc = current_usage
        GC.start(full_mark: true, immediate_sweep: true)
        after_gc = `ps -o rss= -p #{Process.pid}`.to_i / 1024
        
        gc_stats = {
          before_mb: before_gc,
          after_mb: after_gc,
          freed_mb: (before_gc - after_gc),
          gc_stats: GC.stat,
          generation_stats: collect_generation_stats
        }

        Rails.logger.info("GC completed: #{gc_stats.to_json}")
        
        if after_gc > (threshold * 1.3)
          Sentry.capture_message(
            "Memory remains high after GC",
            level: 'warning',
            extra: gc_stats
          ) if defined?(Sentry)
        end
      end
    end
  end
end

# Set up periodic memory monitoring in production
if Rails.env.production?
  Rails.application.config.after_initialize do
    # Enable garbage collection profiling
    GC::Profiler.enable

    # Monitor memory usage every 5 minutes
    Thread.new do
      loop do
        begin
          MemoryMonitoring.check_memory_threshold
        rescue => e
          Rails.logger.error("Memory monitoring failed: #{e.message}")
          Sentry.capture_exception(e) if defined?(Sentry)
        ensure
          sleep 300
        end
      end
    end

    # Track memory statistics around each request in production
    ActiveSupport::Notifications.subscribe "process_action.action_controller" do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      
      if rand < 0.1 # Sample 10% of requests
        stats = MemoryMonitoring.memory_stats.merge(
          controller: event.payload[:controller],
          action: event.payload[:action],
          path: event.payload[:path],
          format: event.payload[:format],
          method: event.payload[:method],
          status: event.payload[:status],
          duration: event.duration,
          view_runtime: event.payload[:view_runtime],
          db_runtime: event.payload[:db_runtime]
        )

        Rails.logger.info("Request memory profile: #{stats.to_json}")

        if stats[:memory_usage_mb] > ENV.fetch('REQUEST_MEMORY_THRESHOLD_MB', 512).to_i
          Sentry.capture_message(
            "High memory usage in request",
            level: 'warning',
            extra: stats
          ) if defined?(Sentry)
        end
      end
    end

    # Monitor GC activity and collect profiling data
    Thread.new do
      loop do
        begin
          if GC::Profiler.total_time > 0
            profile_data = {
              gc_time: GC::Profiler.total_time,
              gc_stats: GC.stat,
              gc_profile: GC::Profiler.raw_data.last(5),
              memory_stats: MemoryMonitoring.memory_stats
            }

            Rails.logger.info("GC profile: #{profile_data.to_json}")
            
            if GC::Profiler.total_time > 5.0 # More than 5 seconds
              Sentry.capture_message(
                "High GC overhead detected",
                level: 'warning',
                extra: profile_data
              ) if defined?(Sentry)
            end

            GC::Profiler.clear
          end
        rescue => e
          Rails.logger.error("GC profiling failed: #{e.message}")
          Sentry.capture_exception(e) if defined?(Sentry)
        ensure
          sleep 300
        end
      end
    end
  end
end