namespace :startup do
  desc 'Run startup checks including server and page error detection'
  task check: :environment do
    StartupCheckService.run
  end
end