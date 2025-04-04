namespace :maintenance do
  desc 'Reset courses_count for all users'
  task reset_course_counts: :environment do
    ActiveRecord::Base.transaction do
      User.find_each do |user|
        count = if user.teacher?
          Course.where(user_id: user.id).count
        else
          Grade.where(user_id: user.id).distinct.count(:course_id)
        end
        user.update_column(:courses_count, count)
      end
    end
    puts "Successfully reset course counts for all users"
  end
end