module Admin
  class MetricsController < AdminController
    before_action :authenticate_user!
    before_action :ensure_admin

    def index
      @page_title = "System Metrics"
      @cache_metrics = fetch_cache_metrics
      @database_metrics = collect_database_metrics
      @redis_metrics = collect_redis_metrics
      @job_metrics = collect_job_metrics
      @health_check_results = Rails.application.config.startup_check_results
      @system_metrics = collect_system_metrics
      @performance_metrics = collect_performance_metrics

      respond_to do |format|
        format.html
        format.json { render json: collect_all_metrics }
      end
    end

    def health_check
      StartupHealthCheckJob.perform_later
      flash[:notice] = "Health check initiated. Results will be available shortly."
      redirect_to admin_metrics_path
    end

    private

    def ensure_admin
      unless current_user&.admin?
        redirect_to root_path, alert: 'Access denied. Administrators only.'
      end
    end

    def fetch_cache_metrics
      total_hits = 0
      total_misses = 0

      Rails.cache.redis.with do |redis|
        hits_keys = redis.keys("metrics:*:cache_hits:#{Date.current}")
        misses_keys = redis.keys("metrics:*:cache_misses:#{Date.current}")
        
        hits_keys.each { |key| total_hits += redis.get(key).to_i }
        misses_keys.each { |key| total_misses += redis.get(key).to_i }
      end

      total = total_hits + total_misses
      rate = total.zero? ? 0 : ((total_hits.to_f / total) * 100).round(2)

      { 
        hits: total_hits, 
        misses: total_misses, 
        rate: rate,
        memory_fragmentation: fetch_cache_fragmentation,
        eviction_count: fetch_eviction_count
      }
    end

    def collect_database_metrics
      {
        active_connections: ActiveRecord::Base.connection_pool.connections.count(&:in_use?),
        pool_size: ActiveRecord::Base.connection_pool.size,
        waiting_connections: ActiveRecord::Base.connection_pool.num_waiting_in_queue,
        db_size: fetch_database_size,
        table_counts: fetch_table_counts,
        slow_queries: fetch_slow_queries,
        deadlocks: fetch_deadlocks_count,
        index_stats: fetch_index_statistics,
        table_bloat: fetch_table_bloat
      }
    end

    def collect_redis_metrics
      redis = Redis.new(Rails.application.config_for(:queue))
      info = redis.info

      {
        connected_clients: info["connected_clients"].to_i,
        used_memory_human: info["used_memory_human"],
        peak_memory_human: info["used_memory_peak_human"],
        total_commands: info["total_commands_processed"].to_i,
        uptime_days: info["uptime_in_days"].to_i,
        ops_per_second: info["instantaneous_ops_per_sec"].to_i,
        hit_rate: (info["keyspace_hits"].to_f / (info["keyspace_hits"].to_f + info["keyspace_misses"].to_f) * 100).round(2),
        memory_fragmentation: info["mem_fragmentation_ratio"].to_f,
        blocked_clients: info["blocked_clients"].to_i
      }
    end

    def collect_job_metrics
      {
        enqueued: SolidQueue::Job.joins(:ready_execution).count,
        scheduled: SolidQueue::Job.joins(:scheduled_execution).count,
        failed: SolidQueue::FailedExecution.count,
        active_processes: SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).count,
        completion_rate: calculate_job_completion_rate,
        avg_processing_time: calculate_avg_processing_time,
        error_rate: calculate_job_error_rate,
        queue_latency: calculate_queue_latency
      }
    end

    def collect_system_metrics
      {
        ruby_version: RUBY_VERSION,
        rails_version: Rails::VERSION::STRING,
        environment: Rails.env,
        server_uptime: server_uptime,
        memory_usage: memory_usage,
        load_averages: load_averages,
        disk_usage: fetch_disk_usage,
        network_stats: fetch_network_stats,
        process_count: fetch_process_count,
        cpu_usage: fetch_cpu_usage
      }
    end

    def collect_performance_metrics
      {
        response_times: collect_response_times,
        error_rates: collect_error_rates,
        throughput: collect_throughput_stats,
        active_sessions: collect_active_sessions,
        slow_transactions: collect_slow_transactions
      }
    end

    def collect_all_metrics
      {
        timestamp: Time.current.iso8601,
        cache: @cache_metrics,
        database: @database_metrics,
        redis: @redis_metrics,
        jobs: @job_metrics,
        system: @system_metrics,
        health: @health_check_results,
        performance: @performance_metrics
      }
    end

    private

    def fetch_database_size
      ActiveRecord::Base.connection.select_value(
        "SELECT pg_size_pretty(pg_database_size(current_database()))"
      )
    end

    def fetch_table_counts
      tables = ActiveRecord::Base.connection.tables
      tables.each_with_object({}) do |table, counts|
        counts[table] = ActiveRecord::Base.connection.select_value(
          "SELECT COUNT(*) FROM #{table}"
        )
      end
    end

    def fetch_slow_queries
      ActiveRecord::Base.connection.select_all(
        "SELECT query, calls, total_time, mean_time
         FROM pg_stat_statements
         WHERE total_time > 1000
         ORDER BY total_time DESC
         LIMIT 10"
      ).to_a
    rescue
      []
    end

    def fetch_deadlocks_count
      ActiveRecord::Base.connection.select_value(
        "SELECT deadlocks FROM pg_stat_database WHERE datname = current_database()"
      ).to_i
    rescue
      0
    end

    def fetch_index_statistics
      ActiveRecord::Base.connection.select_all(
        "SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
         FROM pg_stat_all_indexes
         WHERE idx_scan = 0
         AND schemaname NOT IN ('pg_catalog', 'pg_toast')
         ORDER BY schemaname, tablename"
      ).to_a
    rescue
      []
    end

    def fetch_table_bloat
      ActiveRecord::Base.connection.select_all(
        "SELECT
           current_database(), schemaname, tablename, ROUND((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages::FLOAT/otta END)::NUMERIC,1) AS bloat,
           pg_size_pretty(CASE WHEN relpages < otta THEN 0 ELSE (relpages-otta)::BIGINT*bs END) AS waste
         FROM (
           SELECT
             schemaname, tablename, cc.reltuples, cc.relpages, bs,
             CEIL((cc.reltuples*((datahdr+ma-
               (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::FLOAT)) AS otta
           FROM (
             SELECT
               ma,bs,schemaname,tablename,
               (datawidth+(hdr+ma-(CASE WHEN hdr%ma=0 THEN ma ELSE hdr%ma END)))::NUMERIC AS datahdr,
               (maxfracsum*(nullhdr+ma-(CASE WHEN nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
             FROM (
               SELECT
                 schemaname, tablename, hdr, ma, bs,
                 SUM((1-null_frac)*avg_width) AS datawidth,
                 MAX(null_frac) AS maxfracsum,
                 hdr+(
                   SELECT 1+COUNT(*)/8
                   FROM pg_stats s2
                   WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
                 ) AS nullhdr
               FROM pg_stats s, (
                 SELECT
                   (SELECT current_setting('block_size')::NUMERIC) AS bs,
                   CASE WHEN SUBSTRING(v,12,3) IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
                   CASE WHEN v ~ 'mingw32' THEN 8 ELSE 4 END AS ma
                 FROM (SELECT version() AS v) AS foo
               ) AS constants
               GROUP BY 1,2,3,4,5
             ) AS foo
           ) AS rs
           JOIN pg_class cc ON cc.relname = rs.tablename
           JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname
         ) AS sml
         WHERE sml.relpages - otta > 0
         ORDER BY waste DESC
         LIMIT 10"
      ).to_a
    rescue
      []
    end

    def fetch_disk_usage
      `df -h`.split("\n")[1..-1].map do |line|
        fields = line.split
        {
          filesystem: fields[0],
          size: fields[1],
          used: fields[2],
          available: fields[3],
          usage_percent: fields[4],
          mounted_on: fields[5]
        }
      end
    rescue
      []
    end

    def fetch_network_stats
      {
        connections: `netstat -an | wc -l`.to_i,
        listening_ports: `netstat -an | grep LISTEN | wc -l`.to_i
      }
    rescue
      { connections: 0, listening_ports: 0 }
    end

    def fetch_process_count
      `ps aux | grep #{Rails.application.class.module_parent_name} | wc -l`.to_i
    rescue
      0
    end

    def fetch_cpu_usage
      `ps -o %cpu= -p #{Process.pid}`.to_f
    rescue
      0.0
    end

    def collect_response_times
      Rails.cache.fetch("metrics:response_times:#{Date.current}", expires_in: 5.minutes) do
        # Implement your response time collection logic here
        {}
      end
    end

    def collect_error_rates
      Rails.cache.fetch("metrics:error_rates:#{Date.current}", expires_in: 5.minutes) do
        # Implement your error rate collection logic here
        {}
      end
    end

    def collect_throughput_stats
      Rails.cache.fetch("metrics:throughput:#{Date.current}", expires_in: 5.minutes) do
        # Implement your throughput statistics collection logic here
        {}
      end
    end

    def collect_active_sessions
      ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'"
      ).to_i
    rescue
      0
    end

    def collect_slow_transactions
      Rails.cache.fetch("metrics:slow_transactions:#{Date.current}", expires_in: 5.minutes) do
        # Implement your slow transaction collection logic here
        []
      end
    end

    def server_uptime
      `uptime`.strip
    rescue
      "Not available"
    end

    def memory_usage
      `ps -o rss= -p #{Process.pid}`.to_i / 1024
    rescue
      0
    end

    def load_averages
      File.read('/proc/loadavg').split[0..2]
    rescue
      []
    end

    def fetch_cache_fragmentation
      Rails.cache.redis.with do |redis|
        redis.info["mem_fragmentation_ratio"].to_f
      end
    rescue
      0.0
    end

    def fetch_eviction_count
      Rails.cache.redis.with do |redis|
        redis.info["evicted_keys"].to_i
      end
    rescue
      0
    end

    def calculate_job_completion_rate
      total = SolidQueue::Job.count
      completed = SolidQueue::Job.where.not(finished_at: nil).count
      total.zero? ? 0 : ((completed.to_f / total) * 100).round(2)
    end

    def calculate_avg_processing_time
      SolidQueue::Job.where.not(finished_at: nil)
                    .where("started_at IS NOT NULL")
                    .average("EXTRACT(EPOCH FROM (finished_at - started_at))").to_f
    rescue
      0.0
    end

    def calculate_job_error_rate
      total = SolidQueue::Job.count
      failed = SolidQueue::FailedExecution.count
      total.zero? ? 0 : ((failed.to_f / total) * 100).round(2)
    end

    def calculate_queue_latency
      SolidQueue::Job.joins(:ready_execution)
                    .where("scheduled_at < ?", Time.current)
                    .average("EXTRACT(EPOCH FROM (NOW() - scheduled_at))").to_f
    rescue
      0.0
    end
  end
end