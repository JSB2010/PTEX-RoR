module StatisticsHelper
  def grade_distribution_chart_data(grades)
    grades.select(:id, :letter_grade)
          .group(:letter_grade)
          .count
          .transform_keys { |letter| letter || 'N/A' }
  end

  def course_level_distribution_data(courses)
    courses.select(:id, :level)
           .group(:level)
           .count
  end

  def grade_trend_data(grade)
    grade.recent_changes.map do |change|
      {
        from: change["from"],
        to: change["to"],
        date: change["at"]
      }
    end
  end

  def format_percentage(value, precision: 1)
    return "N/A" if value.nil?
    number_to_percentage(value, precision: precision)
  end

  def course_stats_summary(course)
    {
      total_students: course.students.size,
      passing_rate: course.passing_rate,
      class_average: course.class_average,
      grade_distribution: course.grade_distribution
    }
  end

  def gpa_trend_badge(current_gpa, previous_gpa)
    return "" unless previous_gpa

    difference = current_gpa - previous_gpa
    badge_class = case
                 when difference > 0
                   "text-success"
                 when difference < 0
                   "text-danger"
                 else
                   "text-secondary"
                 end

    icon_class = case
                when difference > 0
                  "bi-arrow-up"
                when difference < 0
                  "bi-arrow-down"
                else
                  "bi-dash"
                end

    content_tag(:span, class: badge_class) do
      concat content_tag(:i, nil, class: "bi #{icon_class}")
      concat " #{number_with_precision(difference.abs, precision: 2)}"
    end
  end

  def determine_performance_status(stats)
    if stats[:calculation_time] > 1000 || stats[:cache_hit_rate] < 30
      { label: 'Poor', color: 'danger' }
    elsif stats[:calculation_time] > 500 || stats[:cache_hit_rate] < 50
      { label: 'Fair', color: 'warning' }
    else
      { label: 'Good', color: 'success' }
    end
  end

  def format_calculation_time(time)
    if time > 1000
      "#{(time / 1000.0).round(2)}s"
    else
      "#{time.round(1)}ms"
    end
  end

  def cache_performance_class(rate)
    case rate
    when 0..30 then 'bg-danger'
    when 31..50 then 'bg-warning'
    when 51..75 then 'bg-info'
    else 'bg-success'
    end
  end

  def format_error_type(error_type)
    error_type.to_s
      .split('::')
      .last
      .gsub(/([A-Z])/, ' \1')
      .strip
  end

  def grade_color(grade)
    case grade
    when 'A++', 'A+', 'A', 'A-' then 'success'
    when 'B+', 'B', 'B-' then 'primary'
    when 'C+', 'C', 'C-' then 'warning'
    when 'D+', 'D' then 'info'
    when 'F' then 'danger'
    else 'secondary'
    end
  end

  def completion_progress_class(rate)
    case rate
    when 90..100 then 'bg-success'
    when 75..89 then 'bg-primary'
    when 60..74 then 'bg-info'
    when 40..59 then 'bg-warning'
    else 'bg-danger'
    end
  end
end