module CoursesHelper
  def grade_progress_class(grade)
    case grade
    when 'A++', 'A+', 'A', 'A-'
      'bg-success'
    when 'B+', 'B', 'B-'
      'bg-primary'
    when 'C+', 'C', 'C-'
      'bg-warning'
    when 'D+', 'D'
      'bg-danger'
    else
      'bg-secondary'
    end
  end

  def course_level_badge_class(level)
    case level
    when 'AP'
      'badge bg-danger'
    when 'Honors'
      'badge bg-primary'
    else
      'badge bg-secondary'
    end
  end
end
