module Admin
  class CoursesController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin
    before_action :set_course, only: [:students, :add_students]
    layout 'admin'

    def index
      @courses = Course.includes(:teacher, :students, :grades)
                      .order(:name)
    end

    def students
      @students = @course.grades.includes(:user).map do |grade|
        {
          name: grade.user.full_name,
          email: grade.user.email,
          grade: grade.letter_grade,
          grade_class: grade_badge_class(grade.letter_grade),
          updated_at: grade.updated_at.strftime("%B %d, %Y")
        }
      end

      render json: { students: @students }
    end

    def add_students
      student_ids = params[:student_ids]
      
      if student_ids.present?
        existing_student_ids = @course.student_ids
        new_student_ids = student_ids - existing_student_ids
        
        new_student_ids.each do |student_id|
          @course.grades.create(user_id: student_id)
        end
        
        flash[:notice] = "#{new_student_ids.size} students were successfully added to the course."
      end
      
      redirect_to admin_courses_path
    end

    private

    def set_course
      @course = Course.find(params[:id])
    end

    def ensure_admin
      unless current_user&.admin?
        redirect_to root_path, alert: 'Access denied.'
      end
    end

    def grade_badge_class(letter_grade)
      case letter_grade
      when 'A' then 'success'
      when 'B' then 'primary'
      when 'C' then 'warning'
      else 'danger'
      end
    end
  end
end