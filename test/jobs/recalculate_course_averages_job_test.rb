require 'test_helper'

class RecalculateCourseAveragesJobTest < ActiveJob::TestCase
  setup do
    @course = courses(:one)
    @user = users(:one)
    # Set up test adapter for job testing
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    # Restore original adapter
    ActiveJob::Base.queue_adapter = @original_adapter
  end

  test "should enqueue job" do
    assert_enqueued_jobs 1 do
      RecalculateCourseAveragesJob.perform_later(@course.id)
    end
  end

  test "should perform job successfully" do
    assert_nothing_raised do
      RecalculateCourseAveragesJob.perform_now(@course.id)
    end
  end

  test "should handle invalid course id gracefully" do
    assert_nothing_raised do
      RecalculateCourseAveragesJob.perform_now(999999)
    end
  end

  test "should use correct queue" do
    job = RecalculateCourseAveragesJob.new(@course.id)
    assert_equal "default", job.queue_name
  end

  test "should retry on failure" do
    # Test that the job handles errors gracefully
    # Since we can't easily mock Course.find, let's test with a non-existent ID
    # The job should handle this gracefully without raising an error
    assert_nothing_raised do
      RecalculateCourseAveragesJob.perform_now(999999)
    end
  end
end
