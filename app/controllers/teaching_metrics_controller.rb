class TeachingMetricsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_teacher

  def index
    @courses = current_user.teaching_courses.includes(:students, :grades)
    @course_statistics = collect_course_statistics
    @grade_distributions = collect_grade_distributions
    @student_engagement = collect_student_engagement
    @grade_completion = collect_grade_completion
  end

  private

  def ensure_teacher
    unless current_user&.teacher?
      redirect_to root_path, alert: 'Access denied. Teachers only.'
    end
  end

  def collect_course_statistics
    @courses.map do |course|
      {
        name: course.name,
        total_students: course.students.count,
        class_average: course.grades.average(:numeric_grade)&.round(1) || 0,
        passing_rate: calculate_passing_rate(course),
        recent_activity: course.grades.where('updated_at > ?', 1.week.ago).count
      }
    end
  end

  def collect_grade_distributions
    @courses.map do |course|
      {
        name: course.name,
        distribution: Grade::GRADE_SCALE.keys.map do |grade|
          count = course.grades.where(letter_grade: grade).count
          [grade, count]
        end.to_h
      }
    end
  end

  def collect_student_engagement
    @courses.map do |course|
      {
        name: course.name,
        active_students: course.grades.where('updated_at > ?', 2.weeks.ago)
                              .select(:user_id).distinct.count,
        at_risk_students: course.grades.where('numeric_grade < ?', 70)
                               .select(:user_id).distinct.count
      }
    end
  end

  def collect_grade_completion
    @courses.map do |course|
      total_possible = course.students.count
      completed = course.grades.where.not(numeric_grade: nil).count
      
      {
        name: course.name,
        completed: completed,
        pending: total_possible - completed,
        completion_rate: total_possible.zero? ? 0 : ((completed.to_f / total_possible) * 100).round(1)
      }
    end
  end

  def calculate_passing_rate(course)
    total = course.grades.count
    return 0 if total.zero?
    
    passing = course.grades.where('numeric_grade >= ?', 70).count
    ((passing.to_f / total) * 100).round(1)
  end
end