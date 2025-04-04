# Be sure to restart your server when you modify this file.

# Define basic security headers
Rails.application.config.action_dispatch.default_headers = {
  'X-Frame-Options' => 'DENY',
  'X-Content-Type-Options' => 'nosniff',
  'X-XSS-Protection' => '0',
  'Referrer-Policy' => 'strict-origin-when-cross-origin'
}

# Define Content Security Policy
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.object_src  :none
  policy.script_src  :self
  policy.style_src   :self
  
  # Allow inline styles for development only
  if Rails.env.development?
    policy.style_src :self, :unsafe_inline
    policy.connect_src :self, "http://localhost:3035", "ws://localhost:3035"
  end
end

# Enable automatic nonce generation for script tags
Rails.application.config.content_security_policy_nonce_generator = -> (request) { 
  SecureRandom.base64(16)
}

# Enable nonces in <script> and <style> tags
Rails.application.config.content_security_policy_nonce_directives = %w(script-src style-src)

# Report CSP violations without enforcing the policy in development
Rails.application.config.content_security_policy_report_only = true if Rails.env.development?
