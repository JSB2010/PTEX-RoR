class Grade < ApplicationRecord
  include GradeValidator
  include GradeHistory

  GRADE_SCALE = {
    'A++' => 100.01, # Extra credit
    'A+' => 97.0,
    'A' => 93.0,
    'A-' => 90.0,
    'B+' => 87.0,
    'B' => 83.0,
    'B-' => 80.0,
    'C+' => 77.0,
    'C' => 73.0,
    'C-' => 70.0,
    'D+' => 67.0,
    'D' => 60.0,
    'F' => 0.0
  }.freeze

  belongs_to :user
  belongs_to :course
  
  validates :numeric_grade, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :user_id, uniqueness: { scope: :course_id }
  validates :letter_grade, presence: true
  
  before_validation :sanitize_numeric_grade
  before_save :calculate_letter_grade
  after_commit :trigger_recalculations
  after_create :increment_student_courses_count
  after_destroy :decrement_student_courses_count

  def recent_changes
    grade_history
  end
  
  private
  
  def sanitize_numeric_grade
    return unless numeric_grade
    self.numeric_grade = numeric_grade.to_f.round(2)
  end
  
  def calculate_letter_grade
    self.letter_grade = case numeric_grade.to_f
      when 100.01.. then 'A++' # Extra credit
      when 97..100 then 'A+'
      when 93..96.99 then 'A'
      when 90..92.99 then 'A-'
      when 87..89.99 then 'B+'
      when 83..86.99 then 'B'
      when 80..82.99 then 'B-'
      when 77..79.99 then 'C+'
      when 73..76.99 then 'C'
      when 70..72.99 then 'C-'
      when 67..69.99 then 'D+'
      when 60..66.99 then 'D'
      when 0..59.99 then 'F'
      else 'F'
    end
  end

  def trigger_recalculations
    return if ENV['SKIP_SOLID_QUEUE'] # Skip during database setup

    # Use a single pattern to clear all related caches
    cache_patterns = [
      "#{user.cache_key_with_version}/*",
      "#{course.cache_key_with_version}/*"
    ]
    
    # Clear caches in a single operation
    Rails.cache.delete_multi(cache_patterns)
    
    # Schedule background job with delay
    RecalculateCourseAveragesJob.perform_later(course_id)
  end

  def update_student_courses_count
    User.where(id: user_id).update_all('courses_count = (SELECT COUNT(DISTINCT course_id) FROM grades WHERE user_id = users.id)')
  end

  def increment_student_courses_count
    # Update the counter cache for student's courses
    user.increment!(:courses_count) if user
  end

  def decrement_student_courses_count
    user.decrement!(:courses_count) if user
  end

  def self.recalculate_course_stats(course_id)
    # Efficiently calculate all stats in one query
    stats = select(:id, :numeric_grade, :letter_grade)
           .where(course_id: course_id)
           .group(:letter_grade)
           .select(
             'AVG(numeric_grade) as avg_grade',
             'COUNT(*) as grade_count',
             'COUNT(CASE WHEN numeric_grade >= 60 THEN 1 END) as passing_count'
           )
           .first

    return unless stats

    # Update all cache entries atomically
    Rails.cache.write_multi({
      "course:#{course_id}:average" => stats.avg_grade.to_f.round(2),
      "course:#{course_id}:grade_distribution" => stats.grade_count,
      "course:#{course_id}:passing_rate" => ((stats.passing_count / stats.grade_count.to_f) * 100).round(1)
    }, expires_in: 12.hours)
  end
end
