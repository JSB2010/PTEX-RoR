module ApplicationHelper
  def course_level_badge(level)
    badge_class = case level
                 when 'AP' then 'badge-ap'
                 when 'Honors' then 'badge-honors'
                 else 'badge-regular'
                 end
    
    content_tag(:span, level, class: "badge #{badge_class}")
  end
  
  def avatar_for(user, size: :md)
    size_class = case size
                when :sm then 'w-6 h-6 text-xs'
                when :md then 'w-8 h-8 text-sm'
                when :lg then 'w-12 h-12 text-base'
                end
    
    content_tag(:div, class: "avatar-circle #{size_class}") do
      user.first_name[0].upcase + user.last_name[0].upcase
    end
  end
  
  def flash_icon(type)
    icon_class = case type
                when 'notice', 'success' then 'bi-check-circle'
                when 'alert', 'error' then 'bi-exclamation-circle'
                when 'info' then 'bi-info-circle'
                when 'warning' then 'bi-exclamation-triangle'
                else 'bi-bell'
                end
    
    content_tag(:i, nil, class: "bi #{icon_class} fs-4 me-2")
  end
  
  def grade_status_badge(grade)
    return content_tag(:span, 'Not Graded', class: 'badge bg-secondary') unless grade&.numeric_grade
    
    badge_class = case grade.letter_grade
                 when 'A++' then 'bg-info' # Special color for extra credit
                 when 'A+', 'A', 'A-' then 'bg-success'
                 when 'B+', 'B', 'B-' then 'bg-primary'
                 when 'C+', 'C', 'C-' then 'bg-warning'
                 when 'D+', 'D' then 'bg-danger'
                 else 'bg-danger'
                 end
    
    content_tag(:span, class: "badge #{badge_class} letter-grade") do
      if grade.numeric_grade > 100
        "#{grade.letter_grade} (#{number_with_precision(grade.numeric_grade, precision: 1)}% 🌟)"
      else
        "#{grade.letter_grade} (#{number_with_precision(grade.numeric_grade, precision: 1)}%)"
      end
    end
  end
  
  def nav_link_to(text, path, options = {})
    is_active = current_page?(path) || 
                (options[:controller] && controller_name == options[:controller])
    
    link_to path, class: "nav-link #{is_active ? 'active' : ''}" do
      concat(content_tag(:i, nil, class: "bi bi-#{options[:icon]} me-2")) if options[:icon]
      concat text
    end
  end
end
