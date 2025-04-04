# Configure application-wide error handling
Rails.application.configure do
  config.after_initialize do
    # Configure custom error pages
    config.exceptions_app = ->(env) {
      ErrorsController.action(:show).call(env)
    }

    # Add error tracking subscribers
    ActiveSupport::Notifications.subscribe "process_action.action_controller" do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      exception = event.payload[:exception_object]

      if exception
        error_data = {
          error: {
            class: exception.class.name,
            message: exception.message,
            backtrace: exception.backtrace&.first(10),
            cause: exception.cause&.inspect
          },
          context: {
            controller: event.payload[:controller],
            action: event.payload[:action],
            params: event.payload[:params].except('controller', 'action'),
            format: event.payload[:format],
            method: event.payload[:method],
            path: event.payload[:path],
            status: event.payload[:status],
            view_runtime: event.payload[:view_runtime],
            db_runtime: event.payload[:db_runtime]
          },
          request_id: event.payload[:request_id],
          user_id: event.payload[:user_id],
          timestamp: Time.current.iso8601
        }

        Rails.logger.error(error_data.to_json)

        # Track error metrics
        metric_key = "metrics:error:#{exception.class.name}:#{Time.current.to_i}"
        Rails.cache.write(metric_key, {
          count: Rails.cache.increment("error_count:#{exception.class.name}"),
          last_occurrence: Time.current.iso8601,
          sample_message: exception.message
        }, expires_in: 24.hours)

        # Report to Sentry with enhanced context
        if defined?(Sentry)
          Sentry.set_context('performance', {
            view_runtime: event.payload[:view_runtime],
            db_runtime: event.payload[:db_runtime]
          })

          Sentry.set_context('request', {
            params: event.payload[:params].except('controller', 'action'),
            format: event.payload[:format],
            method: event.payload[:method],
            path: event.payload[:path]
          })

          Sentry.capture_exception(exception)
        end
      end
    end

    # Monitor memory usage and report if critical
    if Rails.env.production?
      memory_threshold = ENV.fetch('MEMORY_THRESHOLD_MB', 1024).to_i # 1GB default

      Thread.new do
        loop do
          begin
            memory_usage = `ps -o rss= -p #{Process.pid}`.to_i / 1024 # Convert to MB
            if memory_usage > memory_threshold
              Rails.logger.warn(
                memory_alert: {
                  usage_mb: memory_usage,
                  threshold_mb: memory_threshold,
                  process_id: Process.pid,
                  timestamp: Time.current.iso8601
                }.to_json
              )

              Sentry.capture_message(
                "High memory usage detected",
                level: 'warning',
                extra: {
                  memory_usage_mb: memory_usage,
                  threshold_mb: memory_threshold
                }
              ) if defined?(Sentry)
            end
          rescue => e
            Rails.logger.error("Memory monitoring failed: #{e.message}")
          ensure
            sleep 300 # Check every 5 minutes
          end
        end
      end
    end
  end

  # Configure custom error responses
  config.action_dispatch.rescue_responses.merge!(
    'ActionController::ParameterMissing' => :bad_request,
    'ActionController::InvalidAuthenticityToken' => :unprocessable_entity,
    'ActionController::UnknownFormat' => :not_acceptable,
    'ActiveRecord::ReadOnlyRecord' => :forbidden,
    'ActiveRecord::RecordNotDestroyed' => :forbidden
  )
end