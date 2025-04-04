Rack::Timeout.register_state_change_observer(:prometheus) do |env|
  begin
    if env['rack-timeout.info'][:state] == :timed_out
      controller = env['action_controller.instance']
      if controller
        Prometheus::Client.registry.get(:request_timeouts_total).increment(
          labels: {
            controller: controller.class.name,
            action: controller.action_name
          }
        )
      end
    end
  rescue StandardError => e
    Rails.logger.error("Failed to record timeout metric: #{e.message}")
  end
end

Rails.application.config.middleware.insert_before(
  Rack::Runtime,
  Rack::Timeout,
  service_timeout: Rails.env.development? ? 60 : ENV.fetch('RACK_TIMEOUT_SERVICE_SECONDS', 30).to_i,
  wait_timeout: Rails.env.development? ? 60 : ENV.fetch('RACK_TIMEOUT_WAIT_SECONDS', 30).to_i,
  wait_overtime: Rails.env.development? ? 90 : ENV.fetch('RACK_TIMEOUT_WAIT_OVERTIME_SECONDS', 60).to_i
)