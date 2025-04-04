module DashboardHelper
  def grade_color(letter_grade)
    case letter_grade
    when 'A+', 'A', 'A-'
      'success'
    when 'B+', 'B', 'B-'
      'info'
    when 'C+', 'C', 'C-'
      'warning'
    when 'D+', 'D'
      'warning'
    when 'F'
      'danger'
    else
      'secondary'
    end
  end
end
