class CoursesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_course, only: [:show, :edit, :update, :destroy, :add_student, :remove_student, :update_grade, :stats]
  before_action :ensure_teacher_or_admin, except: [:index, :show, :stats]
  before_action :ensure_course_access, only: [:show, :edit, :update, :destroy, :add_student, :remove_student, :update_grade, :stats]

  def index
    @courses = fetch_courses
    @total_courses = @courses.size
    @levels = Course::LEVELS
    
    respond_to do |format|
      format.html
      format.json { render json: @courses }
      format.turbo_stream if turbo_frame_request?
    end
  end

  def show
    fresh_when(etag: [@course, @course.grades.maximum(:updated_at)], last_modified: @course.updated_at)

    @grades = []

    if current_user.admin? || current_user.teacher?
      @available_students = fetch_available_students
      @grades = @course.grades.includes(:user).joins(:user).order('users.last_name', 'users.first_name').to_a
      @grade_distribution = @course.average_by_letter_grade
      @passing_rate = @course.passing_rate
    elsif current_user.student?
      @grades = @course.grades.where(user: current_user).to_a
    end
  end

  def new
    @course = Course.new
  end

  def create
    @course = Course.new(course_params)
    @course.teacher = current_user unless current_user.admin?

    if @course.save
      redirect_to @course, notice: 'Course was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @course.update(course_params)
      redirect_to @course, notice: 'Course was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @course.destroy
    redirect_to courses_url, notice: 'Course was successfully deleted.'
  end

  def add_student
    student = User.find(params[:student_id])
    
    if student.student? && !@course.students.include?(student)
      @course.grades.create(user: student)
      respond_to do |format|
        format.html { redirect_to @course, notice: 'Student was successfully added.' }
        format.json { render json: { status: :ok } }
      end
    else
      respond_to do |format|
        format.html { redirect_to @course, alert: 'Failed to add student.' }
        format.json { render json: { error: 'Invalid student' }, status: :unprocessable_entity }
      end
    end
  end

  def remove_student
    grade = @course.grades.find_by!(user_id: params[:student_id])
    
    if grade.destroy
      respond_to do |format|
        format.html { redirect_to @course, notice: 'Student was successfully removed.' }
        format.json { render json: { status: :ok } }
      end
    else
      respond_to do |format|
        format.html { redirect_to @course, alert: 'Failed to remove student.' }
        format.json { render json: { error: 'Failed to remove student' }, status: :unprocessable_entity }
      end
    end
  end

  def update_grade
    grade = @course.grades.find_by!(user_id: params[:student_id])
    
    if grade.update(grade_params)
      respond_to do |format|
        format.html { redirect_to @course, notice: 'Grade was successfully updated.' }
        format.json { render json: { status: :ok } }
      end
    else
      respond_to do |format|
        format.html { redirect_to @course, alert: 'Failed to update grade.' }
        format.json { render json: { errors: grade.errors }, status: :unprocessable_entity }
      end
    end
  end

  def stats
    respond_to do |format|
      format.html { render partial: 'shared/statistics_dashboard', 
                          locals: { stats: course_stats_summary(@course) } }
      format.json { render json: course_stats_summary(@course) }
    end
  end

  private

  def set_course
    @course = Course.includes(:teacher).find(params[:id])
  end

  def course_params
    params.require(:course).permit(:name, :level)
  end

  def grade_params
    params.require(:grade).permit(:letter_grade, :numeric_grade)
  end

  def ensure_teacher_or_admin
    unless current_user.teacher? || current_user.admin?
      respond_to do |format|
        format.html { redirect_to courses_path, alert: 'You must be a teacher or administrator to perform this action.' }
        format.json { render json: { error: 'Unauthorized' }, status: :unauthorized }
      end
    end
  end

  def ensure_course_access
    unless current_user.can_access_course?(@course)
      respond_to do |format|
        format.html { redirect_to courses_path, alert: 'You do not have access to this course.' }
        format.json { render json: { error: 'Unauthorized' }, status: :unauthorized }
      end
    end
  end

  def fetch_courses
    if current_user.admin?
      Course.includes(:teacher, :students).order(:name)
    elsif current_user.teacher?
      current_user.teaching_courses.includes(:students).order(:name)
    else
      current_user.enrolled_courses.includes(:teacher).order(:name)
    end
  end

  def fetch_available_students
    User.where(role: 'Student')
        .where.not(id: @course.student_ids)
        .order(:last_name, :first_name)
  end
end
