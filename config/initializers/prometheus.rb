# frozen_string_literal: true

# Only load Prometheus in production or if explicitly enabled
if Rails.env.production? || ENV['ENABLE_PROMETHEUS'] == 'true'
  # Require the gem since we're using require: false in the Gemfile
  begin
    require 'prometheus/client'

    # Set up default Prometheus registry early
    prometheus = Prometheus::Client.registry

    Rails.application.config.after_initialize do
      # Configure process metrics
      app_version = ENV.fetch('APP_VERSION', '1.0.0')
      process_files = prometheus.gauge(
        :process_opened_files,
        docstring: 'Number of files opened by Ruby process',
        labels: [:app_version]
      )
      # Set value using the correct method signature
      process_files.set(Process.getrlimit(:NOFILE)[0], labels: { app_version: app_version })

      # Register metrics that will be collected by MetricsExporterService
      prometheus.gauge(
        :course_total,
        docstring: 'Total number of courses'
      )

      prometheus.gauge(
        :job_count,
        docstring: 'Total number of jobs'
      )

      prometheus.gauge(
        :failed_jobs_total,
        docstring: 'Total number of failed jobs'
      )

      prometheus.gauge(
        :cache_hit_ratio,
        docstring: 'Cache hit ratio percentage'
      )

      prometheus.gauge(
        :memory_usage_bytes,
        docstring: 'Memory usage in bytes'
      )

      prometheus.gauge(
        :course_calculation_time_seconds,
        docstring: 'Time taken to calculate course metrics',
        labels: [:course_name]
      )

      prometheus.gauge(
        :job_queue_size,
        docstring: 'Number of pending jobs in queue',
        labels: [:queue_name]
      )

      prometheus.gauge(
        :course_calculation_errors_total,
        docstring: 'Total number of course calculation errors',
        labels: [:course_name, :error_type]
      )

      # Add request timeouts counter if not already defined
      unless prometheus.exist?(:request_timeouts_total)
        prometheus.counter(
          :request_timeouts_total,
          docstring: 'Total number of request timeouts',
          labels: [:controller, :action]
        )
      end

      # Update metrics periodically in server mode
      if defined?(Rails::Server)
        Thread.new do
          loop do
            begin
              # Sleep first to allow application to fully initialize
              sleep(ENV.fetch('PROMETHEUS_COLLECTION_INTERVAL', 60).to_i)

              # Only collect metrics if the MetricsExporterService is defined
              if defined?(MetricsExporterService)
                MetricsExporterService.collect_metrics
              end
            rescue StandardError => e
              Rails.logger.error("Prometheus metrics collection failed: #{e.message}")
              Sentry.capture_exception(e) if defined?(Sentry)
            end
          end
        end
      end

      Rails.logger.info "Prometheus metrics configured"
    end
  rescue LoadError => e
    Rails.logger.warn "Could not load prometheus/client: #{e.message}. Skipping configuration."
  end
else
  Rails.logger.info "Prometheus metrics disabled in #{Rails.env} environment"
end