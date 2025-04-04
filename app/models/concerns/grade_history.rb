module GradeHistory
  extend ActiveSupport::Concern

  included do
    before_save :store_grade_change
    after_save :log_grade_change
  end

  private

  def store_grade_change
    return unless will_save_change_to_numeric_grade?
    
    @old_grade = numeric_grade_was
    @new_grade = numeric_grade
    @change_time = Time.current
  end

  def log_grade_change
    return unless @old_grade && @new_grade

    Rails.logger.info(
      change: {
        grade_id: id,
        course_id: course_id,
        student_id: user_id,
        old_grade: @old_grade,
        new_grade: @new_grade,
        letter_grade: letter_grade,
        changed_at: @change_time,
        changed_by: try(:current_user)&.id || 'system'
      }.to_json
    )

    # Store the last 10 grade changes in cache for quick access
    grade_history_key = "grade:#{id}:history"
    current_history = Rails.cache.fetch(grade_history_key, raw: true) { [] }
    
    updated_history = (current_history + [{
      from: @old_grade,
      to: @new_grade,
      at: @change_time
    }]).last(10)
    
    Rails.cache.write(grade_history_key, updated_history, expires_in: 30.days)
  end

  def grade_history
    Rails.cache.fetch("grade:#{id}:history", raw: true) { [] }
  end
end