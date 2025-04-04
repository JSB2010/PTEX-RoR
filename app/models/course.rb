class Course < ApplicationRecord
  include StatisticsMetrics
  include StatisticsErrorHandler

  belongs_to :teacher, class_name: 'User', foreign_key: 'user_id', counter_cache: :courses_count
  has_many :grades, dependent: :destroy
  has_many :students, through: :grades, source: :user
  
  validates :name, presence: true
  validates :level, presence: true, inclusion: { in: %w[Regular Honors AP] }
  validates :user_id, presence: true
  
  validate :teacher_must_be_teacher

  before_validation :set_default_level

  LEVELS = %w[Regular Honors AP].freeze
  GPA_BOOST = {
    'Regular' => 0.0,
    'Honors' => 0.5,
    'AP' => 1.0
  }.freeze

  attr_accessor :student_count, :avg_grade

  scope :by_level, ->(level) { where(level: level) if level.present? }
  scope :search, ->(query) {
    where("LOWER(name) LIKE ?", "%#{query.to_s.downcase}%") if query.present?
  }

  def self.with_stats
    select('courses.*')
      .select('COUNT(DISTINCT grades.user_id) as student_count')
      .select('COALESCE(AVG(grades.numeric_grade), 0.0) as avg_grade')
      .left_joins(:grades)
      .group(:id)
  end

  def student_count
    read_attribute('student_count') || students.count
  end

  def avg_grade
    read_attribute('avg_grade') || class_average
  end

  def class_average
    fetch_cached_stat('average') do
      measure_performance do
        grades.average(:numeric_grade).to_f.round(2)
      end
    end
  end

  def passing_rate
    fetch_cached_stat('passing_rate') do
      measure_performance do
        total = grades.count
        return 0.0 if total.zero?
        
        passing = grades.where('numeric_grade >= ?', 60.0).count
        ((passing.to_f / total) * 100).round(1)
      end
    end
  end

  def grade_distribution
    fetch_cached_stat('grade_distribution') do
      measure_performance do
        distribution = grades.group(:letter_grade).count
        # Sort by count in descending order, then by grade in descending order for ties
        distribution.sort_by { |grade, count| [-count, -grade_value(grade)] }.to_h
      end
    end
  end

  def average_by_letter_grade
    grade_distribution
  end

  def to_s
    "#{name} (#{level})"
  end

  def gpa_boost
    GPA_BOOST[level] || 0.0
  end
  
  private

  def set_default_level
    self.level ||= 'Regular'
  end

  def teacher_must_be_teacher
    if teacher.present? && !teacher.teacher?
      errors.add(:teacher, "must have a Teacher role")
    end
  end

  def fetch_cached_stat(stat_name)
    cache_key = "#{cache_key_with_version}/#{stat_name}"
    cached = true

    Rails.cache.fetch(cache_key, expires_in: 12.hours) do
      cached = false
      with_error_handling { yield }
    end
  ensure
    track_cache_hit(cached) if cached
  end

  def grade_value(grade)
    case grade
    when 'A++' then 12
    when 'A+' then 11
    when 'A' then 10
    when 'A-' then 9
    when 'B+' then 8
    when 'B' then 7
    when 'B-' then 6
    when 'C+' then 5
    when 'C' then 4
    when 'C-' then 3
    when 'D+' then 2
    when 'D' then 1
    else 0
    end
  end
end
