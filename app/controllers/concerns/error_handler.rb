module ErrorHandler
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
    rescue_from ActionController::ParameterMissing, with: :bad_request
    rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_authenticity_token
    rescue_from ActionController::UnknownFormat, with: :unsupported_format
    
    # Handle database connection errors
    rescue_from ActiveRecord::ConnectionNotEstablished, with: :database_unavailable
    rescue_from PG::ConnectionBad, with: :database_unavailable
    rescue_from ActiveRecord::NoDatabaseError, with: :database_unavailable

    # Handle unauthorized access
    rescue_from StandardError do |e|
      case e
      when ActiveRecord::ReadOnlyRecord, ActiveRecord::RecordNotDestroyed
        forbidden(e)
      when ActionController::RoutingError
        not_found(e)
      else
        unauthorized(e) if e.message.include?('Unauthorized')
        internal_server_error(e) unless e.message.include?('Unauthorized')
      end
    end

    private

    def not_found(exception)
      log_error(exception)
      respond_to do |format|
        format.html { render 'shared/404', status: :not_found }
        format.json { render json: { error: 'Resource not found' }, status: :not_found }
        format.any { head :not_found }
      end
    end

    def unprocessable_entity(exception)
      log_error(exception)
      respond_to do |format|
        format.html { render 'shared/422', status: :unprocessable_entity }
        format.json { render json: { errors: exception.record.errors }, status: :unprocessable_entity }
        format.any { head :unprocessable_entity }
      end
    end

    def bad_request(exception)
      log_error(exception)
      respond_to do |format|
        format.html { render 'shared/400', status: :bad_request }
        format.json { render json: { error: exception.message }, status: :bad_request }
        format.any { head :bad_request }
      end
    end

    def unauthorized(exception)
      log_error(exception)
      respond_to do |format|
        format.html { redirect_to root_path, alert: 'You are not authorized to perform this action.' }
        format.json { render json: { error: 'Unauthorized' }, status: :unauthorized }
        format.any { head :unauthorized }
      end
    end

    def forbidden(exception)
      log_error(exception)
      respond_to do |format|
        format.html { render 'shared/403', status: :forbidden }
        format.json { render json: { error: 'Forbidden' }, status: :forbidden }
        format.any { head :forbidden }
      end
    end

    def invalid_authenticity_token(exception)
      log_error(exception)
      respond_to do |format|
        format.html { redirect_to root_path, alert: 'Your session has expired. Please try again.' }
        format.json { render json: { error: 'Invalid authenticity token' }, status: :unprocessable_entity }
        format.any { head :unprocessable_entity }
      end
    end

    def unsupported_format(exception)
      log_error(exception)
      respond_to do |format|
        format.html { render 'shared/406', status: :not_acceptable }
        format.json { render json: { error: 'Unsupported format requested' }, status: :not_acceptable }
        format.any { head :not_acceptable }
      end
    end

    def database_unavailable(exception)
      log_error(exception)
      respond_to do |format|
        format.html { redirect_to status_path }
        format.json { render json: { error: 'Database unavailable', status: 'deploying' }, status: :service_unavailable }
        format.any { head :service_unavailable }
      end
    end

    def internal_server_error(exception)
      log_error(exception)
      @error_message = exception.message
      respond_to do |format|
        format.html { render 'shared/500', status: :internal_server_error }
        format.json { render json: { error: 'Internal server error' }, status: :internal_server_error }
        format.any { head :internal_server_error }
      end
    end

    def log_error(exception)
      Rails.logger.error(
        error: {
          class: exception.class.name,
          message: exception.message,
          backtrace: exception.backtrace&.first(5),
          user_id: extract_user_id(try(:current_user)),
          ip: request.remote_ip,
          params: request.filtered_parameters,
          url: request.url,
          method: request.method,
          controller: params[:controller],
          action: params[:action],
          request_id: request.request_id,
          user_agent: request.user_agent
        }.to_json
      )
      
      # Report to error monitoring service if configured
      Sentry.capture_exception(exception) if defined?(Sentry)
    end

    def extract_user_id(user)
      return nil if user.nil?
      
      if user.respond_to?(:id)
        user.id
      elsif user.is_a?(Array) && user.first.is_a?(Array) && user.first.first.present?
        user.first.first # Extract ID from Warden session array
      end
    end
  end
end