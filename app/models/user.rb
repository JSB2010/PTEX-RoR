class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :lockable,
         authentication_keys: [:login]
         
  attr_accessor :login
         
  # Teacher relationship
  has_many :teaching_courses, class_name: 'Course', foreign_key: 'user_id'
  
  # Student relationship through grades
  has_many :grades
  has_many :enrolled_courses, through: :grades, source: :course
  
  # Scopes
  scope :students, -> { where(role: 'Student') }
  
  def courses
    teacher? ? teaching_courses : enrolled_courses
  end
  
  def courses_count
    teacher? ? teaching_courses.count : enrolled_courses.count
  end
  
  validates :username, presence: true, uniqueness: { case_sensitive: false },
            format: { with: /\A[a-z][a-z]+\z/, message: "must be first initial followed by last name, lowercase only" }
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :role, presence: true, inclusion: { in: %w[Student Teacher Admin] }
  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  
  before_validation :set_default_role
  before_validation :generate_username, on: :create
  
  ROLES = %w[Admin Teacher Student].freeze
  
  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup
    if (login = conditions.delete(:login))
      where(conditions.to_h).where(["lower(username) = :value OR lower(email) = :value",
        { value: login.downcase }]).first
    elsif conditions.has_key?(:username) || conditions.has_key?(:email)
      where(conditions.to_h).first
    end
  end

  def admin?
    role == 'Admin'
  end

  def teacher?
    role == 'Teacher'
  end

  def student?
    role == 'Student'
  end

  def can_access_course?(course)
    admin? || (teacher? && course.user_id == id) || (student? && course.students.include?(self))
  end

  def calculate_gpa(weighted: false)
    cache_key = weighted ? "weighted_gpa" : "unweighted_gpa"
    Rails.cache.fetch([self, cache_key], expires_in: 12.hours) do
      grades_query = grades.joins(:course)
                         .select(:letter_grade, 'courses.level')
                         .where.not(letter_grade: nil)
                         .to_a

      return 0.0 if grades_query.empty?

      grade_points = {
        'A++' => 4.3, 'A+' => 4.0, 'A' => 4.0, 'A-' => 3.7,
        'B+' => 3.3, 'B' => 3.0, 'B-' => 2.7,
        'C+' => 2.3, 'C' => 2.0, 'C-' => 1.7,
        'D+' => 1.3, 'D' => 1.0, 'D-' => 0.7,
        'F' => 0.0
      }

      level_boosts = Course::GPA_BOOST

      total_points = grades_query.sum do |grade|
        base_points = grade_points[grade.letter_grade] || 0.0
        boost = weighted ? (level_boosts[grade.level] || 0.0) : 0.0
        base_points + boost
      end

      (total_points / grades_query.length).round(2)
    end
  end

  def unweighted_gpa
    calculate_gpa(weighted: false)
  end

  def weighted_gpa
    calculate_gpa(weighted: true)
  end

  def honors_ap_courses
    Rails.cache.fetch([self, 'honors_ap_courses'], expires_in: 12.hours) do
      return Course.none unless student?
      Course.select('courses.*, COALESCE(AVG(grades.numeric_grade), 0) as avg_grade')
            .joins(:grades)
            .where(grades: { user_id: id })
            .where(level: ['Honors', 'AP'])
            .group('courses.id')
            .includes(:teacher)
            .to_a
    end
  end

  def full_name
    [first_name, last_name].compact.join(' ')
  end

  def authenticatable_salt
    "#{super}#{session_token}"
  end

  private

  def set_default_role
    self.role = 'Student' if role.blank?
  end

  def generate_username
    return if username.present?
    return if first_name.blank? || last_name.blank?
    
    # Generate username as first initial + last name
    base_username = (first_name[0] + last_name).downcase.gsub(/[^a-z]/, '')
    self.username = base_username
    
    # If username is taken, append numbers until we find a unique one
    counter = 1
    while User.exists?(username: username)
      self.username = "#{base_username}#{counter}"
      counter += 1
    end
  end

  def session_token
    encrypted_password.present? ? encrypted_password[0,29] : ''
  end
end
