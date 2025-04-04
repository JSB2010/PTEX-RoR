class RecalculateCourseAveragesJob < ApplicationJob
  queue_as :default
  
  def perform(course_id)
    return unless Course.exists?(course_id)
    
    # Use the new optimized method to recalculate all course statistics at once
    Grade.recalculate_course_stats(course_id)
  end
end