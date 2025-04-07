# frozen_string_literal: true

# Logging optimization configuration
#
# This initializer sets up logging optimization to reduce disk usage.

# Configure log level
Rails.logger.level = ENV.fetch('LOG_LEVEL', 'info').to_sym

# Configure log filtering
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn,
  :password_confirmation, :secret_token, :api_key, :auth_token, :access_token,
  :refresh_token, :bearer_token, :client_secret, :cookie, :session, :key
]

# Configure log silencing
Rails.application.config.assets.quiet = true
