namespace :demo do
  desc "Load demo household data (refuses to run in production)"
  task seed: :environment do
    DemoSeeder.new.run
  end

  desc "Reset the database, load reference seeds, then demo data"
  task reset: %w[db:reset demo:seed]
end
