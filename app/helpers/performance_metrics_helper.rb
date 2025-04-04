module PerformanceMetricsHelper
  def cache_performance_class(rate)
    if rate >= 80
      'bg-success'
    elsif rate >= 60
      'bg-info'
    elsif rate >= 40
      'bg-warning'
    else
      'bg-danger'
    end
  end

  def format_error_type(type)
    type.to_s.humanize.titleize
  end

  def format_calculation_time(time)
    return 'N/A' unless time
    
    if time >= 1000
      "#{number_with_precision(time / 1000.0, precision: 2)}s"
    else
      "#{number_with_precision(time, precision: 1)}ms"
    end
  end

  def cache_hit_rate_badge(rate)
    label = case rate
    when 80..Float::INFINITY then ['Excellent', 'success']
    when 60...80 then ['Good', 'info']
    when 40...60 then ['Fair', 'warning']
    else ['Poor', 'danger']
    end

    content_tag(:span, label[0], class: "badge bg-#{label[1]}")
  end

  def format_memory_usage(bytes)
    return '0 B' if bytes.nil? || bytes.zero?

    units = ['B', 'KB', 'MB', 'GB']
    exp = (Math.log(bytes) / Math.log(1024)).floor
    exp = units.size - 1 if exp > units.size - 1

    "#{number_with_precision(bytes.to_f / 1024**exp, precision: 2)} #{units[exp]}"
  end

  def relative_time_in_words(timestamp)
    if timestamp > 1.day.ago
      time_ago_in_words(timestamp) + ' ago'
    else
      I18n.l(timestamp, format: :short)
    end
  end

  def performance_status_icon(status)
    case status
    when 'ok', 'good'
      content_tag(:i, '', class: 'bi bi-check-circle-fill text-success')
    when 'warning'
      content_tag(:i, '', class: 'bi bi-exclamation-triangle-fill text-warning')
    when 'critical'
      content_tag(:i, '', class: 'bi bi-x-circle-fill text-danger')
    else
      content_tag(:i, '', class: 'bi bi-question-circle-fill text-muted')
    end
  end

  def memory_usage_indicator(used_mb, total_mb)
    percentage = (used_mb / total_mb.to_f * 100).round
    status_class = case percentage
    when 0..70 then 'success'
    when 71..85 then 'warning'
    else 'danger'
    end

    content_tag(:div, class: 'progress') do
      content_tag(:div, "#{percentage}%",
        class: "progress-bar bg-#{status_class}",
        role: 'progressbar',
        style: "width: #{percentage}%",
        'aria-valuenow' => percentage,
        'aria-valuemin' => 0,
        'aria-valuemax' => 100
      )
    end
  end

  def grade_color(grade)
    case grade
    when 'A' then 'success'
    when 'B' then 'primary'
    when 'C' then 'info'
    when 'D' then 'warning'
    else 'danger'
    end
  end

  def health_status_color(status)
    case status.to_s
    when 'success' then 'success'
    when 'warning' then 'warning'
    else 'danger'
    end
  end

  def format_memory(bytes)
    number_to_human_size(bytes)
  end

  def format_duration(seconds)
    if seconds >= 86400 # 1 day
      "#{(seconds / 86400).round(1)} days"
    elsif seconds >= 3600 # 1 hour
      "#{(seconds / 3600).round(1)} hours"
    elsif seconds >= 60 # 1 minute
      "#{(seconds / 60).round(1)} minutes"
    else
      "#{seconds.round(1)} seconds"
    end
  end
end