namespace :price_checks do
  desc "Import price checks from a CSV: [path], else price_checks.csv in the app root"
  task :import, [:path] => :environment do |_task, args|
    PriceChecks::CsvImporter.import_and_report(args[:path])
  rescue CsvCheckImporter::Error => error
    abort error.message
  end

  desc "Write a reproducible sample of price checks for the current catalog: [path] (default price_checks.csv), [rows] (default 100000)"
  task :generate_sample, %i[path rows] => :environment do |_task, args|
    args.with_defaults(path: Rails.root.join("price_checks.csv").to_s, rows: "100000")

    written = PriceChecks::SampleGenerator.new(row_count: Integer(args[:rows])).write(args[:path])
    puts "Wrote #{written} price checks to #{args[:path]}"
  rescue ArgumentError => error
    abort error.message
  end
end
