module AdminHelper
  def system_status_badge(status)
    badge_class = status ? 'success' : 'danger'
    content_tag(:span, class: "badge bg-#{badge_class}") do
      content_tag(:i, '', class: "bi bi-circle-fill me-1") +
      (status ? 'Operational' : 'Issue Detected')
    end
  end

  def format_bytes(bytes)
    return '0 B' if bytes.nil? || bytes.zero?

    units = ['B', 'KB', 'MB', 'GB', 'TB']
    exp = (Math.log(bytes) / Math.log(1024)).floor
    exp = units.length - 1 if exp > units.length - 1

    "#{(bytes.to_f / 1024**exp).round(2)} #{units[exp]}"
  end

  def format_duration(seconds)
    return '0s' if seconds.nil? || seconds.zero?

    days = seconds / 86400
    hours = (seconds % 86400) / 3600
    minutes = (seconds % 3600) / 60
    remaining_seconds = seconds % 60

    if days > 0
      "#{days}d #{hours}h"
    elsif hours > 0
      "#{hours}h #{minutes}m"
    elsif minutes > 0
      "#{minutes}m #{remaining_seconds}s"
    else
      "#{remaining_seconds}s"
    end
  end

  def status_icon(status)
    if status
      content_tag(:i, '', class: 'bi bi-check-circle-fill text-success')
    else
      content_tag(:i, '', class: 'bi bi-exclamation-circle-fill text-danger')
    end
  end

  def course_level_badge(level)
    badge_class = {
      'AP' => 'danger',
      'Honors' => 'warning',
      'Regular' => 'primary'
    }[level] || 'secondary'

    content_tag(:span, level, class: "badge bg-#{badge_class}")
  end

  def format_percentage(value, precision = 1)
    return 'N/A' if value.nil?
    number_to_percentage(value, precision: precision)
  end

  def admin_breadcrumb(items)
    content_tag(:nav, 'aria-label': 'breadcrumb') do
      content_tag(:ol, class: 'breadcrumb') do
        items.map.with_index do |(text, path), index|
          if index == items.length - 1
            content_tag(:li, text, class: 'breadcrumb-item active')
          else
            content_tag(:li, class: 'breadcrumb-item') do
              link_to(text, path)
            end
          end
        end.join.html_safe
      end
    end
  end

  def format_memory(bytes)
    return '0 MB' if bytes.nil? || bytes.zero?
    
    mb = bytes / 1024.0 / 1024.0
    if mb >= 1024
      gb = mb / 1024.0
      "%.2f GB" % gb
    else
      "%.2f MB" % mb
    end
  end

  def system_metric_card(title:, value:, icon:, status: true, tooltip: nil)
    content_tag(:div, class: 'card h-100') do
      content_tag(:div, class: 'card-body') do
        content_tag(:div, class: 'd-flex align-items-center') do
          status_indicator = content_tag(:div, class: "stat-icon #{status ? 'success' : 'danger'}") do
            content_tag(:i, '', class: "bi bi-#{icon} fs-4")
          end

          metric_content = content_tag(:div, class: 'ms-3') do
            concat content_tag(:h6, title, class: 'card-subtitle text-muted mb-1')
            concat content_tag(:h4, value, class: 'card-title mb-0')
            if tooltip
              concat content_tag(:small, tooltip, class: 'text-muted d-block mt-1')
            end
          end

          status_indicator + metric_content
        end
      end
    end
  end
end