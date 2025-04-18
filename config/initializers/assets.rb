# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
Rails.application.config.assets.paths << Rails.root.join("node_modules")
Rails.application.config.assets.paths << Rails.root.join('vendor', 'stylesheets')

# Precompile additional assets.
Rails.application.config.assets.precompile += %w( bootstrap.min.js popper.js application.js auth.css *.png *.jpg *.jpeg *.gif )

# Enable the asset pipeline
Rails.application.config.assets.enabled = true

# Initialize configuration defaults for originally generated Rails version.
Rails.application.config.assets.css_compressor = nil
