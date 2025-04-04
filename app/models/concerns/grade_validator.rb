module GradeValidator
  extend ActiveSupport::Concern

  included do
    before_save :track_grade_change
    validate :validate_grade_change
  end

  private

  def track_grade_change
    return unless will_save_change_to_numeric_grade?
    
    @previous_grade = numeric_grade_was
    @grade_change_amount = numeric_grade.to_f - (@previous_grade || 0).to_f
  end

  def validate_grade_change
    return unless will_save_change_to_numeric_grade?
    return if new_record?

    # Don't allow grade changes more than 50 points at once (configurable)
    max_change = 50.0
    if @grade_change_amount && @grade_change_amount.abs > max_change
      errors.add(:numeric_grade, "cannot be changed by more than #{max_change} points at once")
    end

    # Don't allow decreasing grades that were already above 100 (extra credit)
    if @previous_grade.to_f > 100 && numeric_grade.to_f < @previous_grade.to_f
      errors.add(:numeric_grade, "cannot decrease an extra credit grade")
    end
  end
end