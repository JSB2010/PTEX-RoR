module StatisticsErrorHandler
  extend ActiveSupport::Concern

  def with_error_handling
    yield
  rescue StandardError => error
    handle_statistics_error(error)
  end

  private

  def handle_statistics_error(error)
    Rails.logger.error(
      error: {
        class: error.class.name,
        message: error.message,
        backtrace: error.backtrace&.first(5),
        context: {
          course_id: try(:id),
          total_students: try(:students)&.count,
          total_grades: try(:grades)&.count
        }
      }.to_json
    )
    # Report to error monitoring service if configured
    Sentry.capture_exception(error) if defined?(Sentry)
    
    # Return safe default values
    case error.class.name
    when "ZeroDivisionError"
      0.0
    when "NoMethodError"
      nil
    else
      raise error if Rails.env.development? || Rails.env.test?
      0.0 # Safe default for production
    end
  end
end