# frozen_string_literal: true

# Asset optimization configuration
#
# This initializer sets up asset optimization to improve performance.

# Configure asset compression
Rails.application.config.assets.compress = true

# Configure asset digest
Rails.application.config.assets.digest = true

# Configure asset version
Rails.application.config.assets.version = '1.0'

# Configure asset host
if ENV['ASSET_HOST'].present?
  Rails.application.config.asset_host = ENV['ASSET_HOST']
end

# Configure asset cache buster
Rails.application.config.assets.cache_limit = ENV.fetch('ASSET_CACHE_LIMIT', 50).to_i.megabytes

# Configure asset paths
Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'fonts')
Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'images')
Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'videos')

# Configure asset precompilation
Rails.application.config.assets.precompile += %w[
  *.png *.jpg *.jpeg *.gif *.svg *.eot *.ttf *.woff *.woff2
  application.css application.js
]

# Configure asset debugging
Rails.application.config.assets.debug = false

# Configure asset quiet
Rails.application.config.assets.quiet = true

# Configure asset prefix
if ENV['ASSET_PREFIX'].present?
  Rails.application.config.assets.prefix = ENV['ASSET_PREFIX']
end

# Configure asset CDN
if ENV['ASSET_CDN'].present?
  Rails.application.config.action_controller.asset_host = ENV['ASSET_CDN']
end

# Configure asset gzip
Rails.application.config.assets.gzip = true

# Configure asset source maps
Rails.application.config.sass.inline_source_maps = false

# Configure asset cache headers
Rails.application.config.public_file_server.headers = {
  'Cache-Control' => "public, max-age=#{ENV.fetch('ASSET_CACHE_MAX_AGE', 31536000)}"
}
