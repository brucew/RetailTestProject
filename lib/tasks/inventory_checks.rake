namespace :inventory_checks do
  desc "Import inventory checks from a CSV: [path], else inventory_checks.csv, else tracking_events.csv in the app root"
  task :import, [:path] => :environment do |_task, args|
    path = InventoryChecks::CsvImporter.locate_source(args[:path])
    puts "Importing inventory checks from #{path}"

    result = InventoryChecks::CsvImporter.new(path).import
    puts "Inventory checks: #{result.summary}"
    result.rejection_samples.each { |rejection| puts "  rejected line #{rejection.line}: #{rejection.reason}" }
  rescue InventoryChecks::CsvImporter::SourceNotFoundError, InventoryChecks::CsvImporter::MissingHeadersError => error
    abort error.message
  end
end
