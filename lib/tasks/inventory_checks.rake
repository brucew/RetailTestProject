namespace :inventory_checks do
  desc "Import inventory checks from a CSV: [path], else inventory_checks.csv, else tracking_events.csv in the app root"
  task :import, [:path] => :environment do |_task, args|
    InventoryChecks::CsvImporter.import_and_report(args[:path])
  rescue CsvCheckImporter::Error => error
    abort error.message
  end
end
