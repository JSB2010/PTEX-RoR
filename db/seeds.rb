# This file contains seed data for the development environment
require 'faker'

puts "Clearing existing data..."
Grade.destroy_all
Course.destroy_all
User.destroy_all

# Initialize a hash to store passwords
seed_passwords = {}

def generate_password
  # Generate a secure random password that meets requirements
  "Password#{rand(100..999)}!"
end

def generate_username(first_name, last_name)
  # Generate username as first initial + last name, lowercase only
  base = (first_name[0] + last_name).downcase.gsub(/[^a-z]/, '')
  counter = 1
  username = base
  
  while User.exists?(username: username)
    username = "#{base}#{counter}"
    counter += 1
  end
  
  username
end

puts "Creating admin user..."
admin_password = 'Admin123!'
admin = User.create!(
  first_name: 'Admin',
  last_name: 'User',
  email: 'admin@school.edu',
  role: 'Admin',
  username: 'admin',
  password: admin_password,
  password_confirmation: admin_password,
  seed_password: admin_password
)
seed_passwords['admin'] = admin_password

puts "Creating teachers..."
teachers = [
  {
    first_name: 'John',
    last_name: 'Smith',
    email: 'jsmith@school.edu',
    role: 'Teacher'
  },
  {
    first_name: 'Mary',
    last_name: 'Johnson',
    email: 'mjohnson@school.edu',
    role: 'Teacher'
  },
  {
    first_name: 'Robert',
    last_name: 'Garcia',
    email: 'rgarcia@school.edu',
    role: 'Teacher'
  }
]

created_teachers = teachers.map do |teacher_data|
  username = generate_username(teacher_data[:first_name], teacher_data[:last_name])
  password = generate_password
  seed_passwords[username] = password
  
  User.create!(
    first_name: teacher_data[:first_name],
    last_name: teacher_data[:last_name],
    email: teacher_data[:email],
    role: teacher_data[:role],
    username: username,
    password: password,
    password_confirmation: password,
    seed_password: password
  )
end

puts "Creating students..."
# Create 30 students with realistic names
created_students = 30.times.map do
  first_name = Faker::Name.unique.first_name
  last_name = Faker::Name.unique.last_name
  username = generate_username(first_name, last_name)
  password = generate_password
  seed_passwords[username] = password
  
  User.create!(
    first_name: first_name,
    last_name: last_name,
    email: "#{username}@school.edu",
    role: 'Student',
    username: username,
    password: password,
    password_confirmation: password,
    seed_password: password
  )
end

puts "Creating courses..."
courses = [
  {
    name: 'Advanced Mathematics',
    description: 'Advanced topics in mathematics including calculus and linear algebra',
    teacher: created_teachers[0],
    level: 'AP'
  },
  {
    name: 'Physics',
    description: 'Introduction to physics including mechanics and thermodynamics',
    teacher: created_teachers[0],
    level: 'AP'
  },
  {
    name: 'English Literature',
    description: 'Study of classic literature and writing techniques',
    teacher: created_teachers[1],
    level: 'Honors'
  },
  {
    name: 'World History',
    description: 'Comprehensive study of world history and civilizations',
    teacher: created_teachers[1],
    level: 'Honors'
  },
  {
    name: 'Chemistry',
    description: 'Study of matter, its properties, and transformations',
    teacher: created_teachers[2],
    level: 'Honors'
  },
  {
    name: 'Biology',
    description: 'Study of living organisms and their interactions',
    teacher: created_teachers[2],
    level: 'Regular'
  },
  {
    name: 'Computer Science',
    description: 'Introduction to programming and computer science concepts',
    teacher: created_teachers[0],
    level: 'AP'
  },
  {
    name: 'Spanish',
    description: 'Spanish language and culture studies',
    teacher: created_teachers[1],
    level: 'Regular'
  },
  {
    name: 'Art History',
    description: 'Survey of art throughout human history',
    teacher: created_teachers[2],
    level: 'Regular'
  }
]

created_courses = courses.map { |course| Course.create!(course) }

puts "Adding students to courses and creating grades..."

# More realistic grade distribution based on course level
def generate_grade(course_level)
  case course_level
  when 'AP'
    ['A', 'B', 'A', 'B', 'A', 'C'].sample
  when 'Honors'
    ['A', 'B', 'B', 'C', 'A', 'B'].sample
  else # Regular
    ['A', 'B', 'C', 'B', 'C', 'B'].sample
  end
end

def numeric_grade_for_letter(letter)
  case letter
  when 'A' then rand(90..100)
  when 'B' then rand(80..89)
  when 'C' then rand(70..79)
  when 'D' then rand(60..69)
  else rand(50..59)
  end
end

# Assign students to random courses with appropriate grade distributions
created_courses.each do |course|
  # Each course gets between 15 and 25 students
  student_count = rand(15..25)
  students = created_students.sample(student_count)
  
  students.each do |student|
    letter_grade = generate_grade(course.level)
    numeric = numeric_grade_for_letter(letter_grade)
    
    course.grades.create!(
      user: student,
      letter_grade: letter_grade,
      numeric_grade: numeric
    )
  end
end

# Store all passwords in Rails cache
Rails.cache.write('seed_passwords', seed_passwords, expires_in: 1.year)

puts "Seed data creation completed!"
