namespace :price_checks do
  desc "Import price checks from a CSV: [path], else price_checks.csv in the app root"
  task :import, [:path] => :environment do |_task, args|
    PriceChecks::CsvImporter.import_and_report(args[:path])
  rescue CsvCheckImporter::Error => error
    abort error.message
  end
end
