class Rack::Attack
  ### Configure Cache ###
  Rack::Attack.cache.store = Rails.cache

  ### Safelist Trusted IPs ###
  safelist('allow from localhost') do |req|
    '127.0.0.1' == req.ip || '::1' == req.ip
  end

  # Allow IPs in trusted ranges (e.g., internal network)
  safelist('allow internal network') do |req|
    trusted_networks = ENV.fetch('TRUSTED_NETWORKS', '').split(',')
    trusted_networks.any? { |network| IPAddr.new(network).include?(req.ip) }
  end

  # Skip rate limiting in development
  safelist('allow all in development') do |req|
    !Rails.env.production?
  end

  ### Rate Limits ###
  
  # Global rate limit per IP
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets', '/packs', '/images')
  end

  # Throttle login attempts by IP
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.ip
    end
  end

  # Stricter throttle for failed logins
  throttle('logins/failed/ip', limit: 3, period: 5.minutes) do |req|
    if req.path == '/users/sign_in' && req.post? && req.env['warden.custom.authentication_result'] == :failure
      req.ip
    end
  end

  # Throttle login attempts by email
  throttle('logins/email', limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.params.dig('user', 'email')&.to_s&.downcase&.gsub(/\s+/, '')
    end
  end

  # Throttle password reset requests
  throttle('password_reset/ip', limit: 3, period: 15.minutes) do |req|
    if req.path == '/users/password' && req.post?
      req.ip
    end
  end

  # Throttle grade updates
  throttle('grade_updates/ip', limit: 30, period: 1.minute) do |req|
    if req.path =~ /\/courses\/\d+\/update_grade/ && req.patch?
      req.ip
    end
  end

  # Throttle bulk operations
  throttle('bulk_operations/ip', limit: 10, period: 5.minutes) do |req|
    if req.path =~ /bulk|batch|mass|multiple/ && %w[POST PATCH PUT DELETE].include?(req.method)
      req.ip
    end
  end

  # API rate limits with tiers
  throttle('api/authenticated', limit: 300, period: 1.minute) do |req|
    if req.env['warden'].authenticated? && req.path.start_with?('/api')
      req.ip
    end
  end

  throttle('api/anonymous', limit: 60, period: 1.minute) do |req|
    if !req.env['warden'].authenticated? && req.path.start_with?('/api')
      req.ip
    end
  end

  # Performance metrics rate limits
  throttle('performance_metrics/api/authenticated', limit: 300, period: 1.minute) do |req|
    if req.path.start_with?('/performance_metrics') && req.get? && req.env['warden'].authenticated?
      req.ip
    end
  end

  throttle('performance_metrics/api/anonymous', limit: 60, period: 1.minute) do |req|
    if req.path.start_with?('/performance_metrics') && req.get? && !req.env['warden'].authenticated?
      req.ip
    end
  end

  ### Security Blocks ###

  # Block known bad actors
  blocklist('block known attackers') do |req|
    Rack::Attack::Allow2Ban.filter(req.ip,
      maxretry: 10,
      findtime: 1.minute,
      bantime: 1.hour
    ) do
      CGI.unescape(req.query_string) =~ %r{/etc/passwd} ||
      CGI.unescape(req.query_string) =~ %r{/etc/shadow} ||
      CGI.unescape(req.query_string) =~ %r{/proc/} ||
      CGI.unescape(req.query_string) =~ %r{/etc/hosts} ||
      CGI.unescape(req.query_string) =~ %r{/wp-} ||
      CGI.unescape(req.query_string) =~ %r{/admin/} ||
      req.path =~ /wp-admin/ ||
      req.path =~ /wp-login/ ||
      req.path =~ /xmlrpc.php/ ||
      req.path =~ /phpMyAdmin/ ||
      req.path =~ /\.php$/
    end
  end

  # Block suspicious requests
  blocklist('block_suspicious_access') do |req|
    Rack::Attack::Allow2Ban.filter(req.ip,
      maxretry: 5,
      findtime: 2.minutes,
      bantime: 1.hour
    ) do
      suspicious_request?(req)
    end
  end

  # Block repeated unauthorized requests
  blocklist('block_after_repeated_unauthorized') do |req|
    Rack::Attack::Allow2Ban.filter(req.ip,
      maxretry: 10,
      findtime: 5.minutes,
      bantime: 2.hours
    ) do
      req.env["rack.attack.match_count"].to_i > 0 &&
      req.env["warden.custom.authentication_result"] == :failure
    end
  end

  ### Response Configuration ###

  # Custom throttled responder
  self.throttled_responder = lambda do |env|
    match_data = env['rack.attack.match_data']
    now = Time.now

    headers = {
      'Content-Type' => 'application/json',
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + (match_data[:period] - now.to_i % match_data[:period])).to_s,
      'Retry-After' => (match_data[:period] - now.to_i % match_data[:period]).to_s
    }

    [
      429,
      headers,
      [{ 
        error: "Rate limit exceeded. Please retry later.",
        retry_after: (match_data[:period] - now.to_i % match_data[:period]),
        details: match_data[:discriminator]
      }.to_json]
    ]
  end

  # Custom blocklist responder
  self.blocklisted_responder = lambda do |env|
    [
      403,
      {'Content-Type' => 'application/json'},
      [{ error: "Access denied" }.to_json]
    ]
  end

  private

  def self.suspicious_request?(req)
    return true if req.path =~ /\.(php|asp|aspx|jsp|cgi)$/i
    return true if req.path =~ /(%00|%0d|%0a)/i # Null byte and CRLF injection
    return true if req.user_agent =~ /^$/i # Blank user agent
    return true if req.user_agent =~ /(masscan|nikto|sqlmap|nmap|nessus|acunetix|metasploit)/i
    return true if req.path =~ /(\.env|composer\.json|yarn\.lock|package\.json|Gemfile)$/i
    
    # Check for suspicious query parameters
    if req.query_string
      decoded = CGI.unescape(req.query_string)
      return true if decoded =~ /<script|javascript:|data:/i # XSS attempts
      return true if decoded =~ /union.*select|information_schema/i # SQL injection
    end

    false
  end
end