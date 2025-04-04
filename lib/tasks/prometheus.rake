namespace :prometheus do
  desc 'Start Prometheus metrics endpoint'
  task start_metrics_server: :environment do
    require 'rack'
    require 'prometheus/client/rack/collector'
    require 'prometheus/client/rack/exporter'
    
    app = Rack::Builder.new do
      use Rack::Deflater
      use Prometheus::Client::Rack::Collector
      use Prometheus::Client::Rack::Exporter

      run ->(_) { [200, {'Content-Type' => 'text/html'}, ['Metrics endpoint running']] }
    end

    Rack::Handler::WEBrick.run(app,
      Port: ENV.fetch('PROMETHEUS_PORT', 9394),
      Host: '0.0.0.0',
      AccessLog: []
    )
  end

  desc 'Update Prometheus metrics'
  task update_metrics: :environment do
    MetricsExporterService.collect_metrics
  end

  desc 'Reset Prometheus metrics'
  task reset_metrics: :environment do
    MetricsExporterService.reset_metrics
  end
end