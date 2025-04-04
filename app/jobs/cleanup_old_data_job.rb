class CleanupOldDataJob < ApplicationJob
  queue_as :maintenance

  def perform(options = {})
    Rails.logger.info "Starting cleanup job at #{Time.current}"

    # Clean up old grades
    if options[:grades]
      cleanup_grades(options[:grade_age] || 1.year.ago)
    end

    # Clean up empty courses
    if options[:courses]
      cleanup_courses(options[:course_age] || 6.months.ago)
    end

    # Clean up old cache entries
    if options[:cache]
      cleanup_cache
    end

    # Clean up old job records
    if options[:jobs]
      cleanup_job_records(options[:job_age] || 1.month.ago)
    end

    Rails.logger.info "Cleanup job completed at #{Time.current}"
  end

  private

  def cleanup_grades(cutoff_date)
    count = Grade.where('created_at < ?', cutoff_date).delete_all
    Rails.logger.info "Cleaned up #{count} old grades"
  end

  def cleanup_courses(cutoff_date)
    count = Course.where('created_at < ? AND students_count = 0', cutoff_date).delete_all
    Rails.logger.info "Cleaned up #{count} empty courses"
  end

  def cleanup_cache
    Rails.cache.cleanup
    Rails.logger.info "Cache cleanup completed"
  end

  def cleanup_job_records(cutoff_date)
    count = SolidQueue::Job
      .where('completed_at < ? OR failed_at < ?', cutoff_date, cutoff_date)
      .delete_all
    Rails.logger.info "Cleaned up #{count} old job records"
  end
end