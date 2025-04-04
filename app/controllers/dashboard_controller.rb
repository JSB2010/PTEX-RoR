class DashboardController < ApplicationController
  before_action :authenticate_user!
  
  def show
    if current_user.teacher?
      # Fetch course stats using a subquery to avoid modification issues
      stats_query = current_user.courses
                               .select('courses.id, COUNT(DISTINCT grades.user_id) as student_count, COALESCE(AVG(grades.numeric_grade), 0.0) as avg_grade')
                               .left_joins(:grades)
                               .group('courses.id')
                               .to_h { |c| [c.id, { student_count: c.student_count, avg_grade: c.avg_grade }] }
      # Load courses without unnecessary associations
      @courses = current_user.courses
      
      # Attach stats to courses
      @courses.each do |course|
        stats = stats_query[course.id] || { student_count: 0, avg_grade: 0.0 }
        course.instance_variable_set(:@student_count, stats[:student_count])
        course.instance_variable_set(:@avg_grade, stats[:avg_grade])
      end
      @total_students = stats_query.values.sum { |s| s[:student_count] }
    else
      @courses = Course.includes(:teacher, :grades)
                      .joins(:grades)
                      .where(grades: { user_id: current_user.id })
                      .distinct
      @unweighted_gpa = current_user.unweighted_gpa
      @weighted_gpa = current_user.weighted_gpa
      @honors_ap_courses = current_user.honors_ap_courses
    end
  end
end
