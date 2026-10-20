require "csv"

# Bulk-imports one kind of check (inventory, price, ...) from a CSV export (D9).
#
# Rows are streamed, parsed against preloaded store and product ids, and
# inserted in batches with ON CONFLICT DO NOTHING on the kind's exact-duplicate
# index (D6, A4), so a re-run inserts nothing. The whole file is one
# transaction (A5): a file that can't be read leaves the table as it was.
#
# Each kind of check is a subclass that declares what it imports:
#
#   class PriceChecks::CsvImporter < CsvCheckImporter
#     imports PriceCheck, parsed_by: PriceChecks::CsvRowParser,
#                         unique_by: :index_price_checks_on_store_product_time_price,
#                         default_file_names: %w[price_checks.csv]
#   end
class CsvCheckImporter
  class Error < StandardError; end
  class MissingHeadersError < Error; end
  class SourceNotFoundError < Error; end

  Result = Data.define(:rows_read, :inserted, :duplicates, :rejected, :rejection_samples) do
    def summary
      "rows read=#{rows_read} inserted=#{inserted} duplicates=#{duplicates} rejected=#{rejected}"
    end
  end

  Rejection = Data.define(:line, :reason)

  class << self
    attr_reader :check_class, :row_parser_class, :unique_index, :default_file_names

    def imports(check_class, parsed_by:, unique_by:, default_file_names:)
      @check_class = check_class
      @row_parser_class = parsed_by
      @unique_index = unique_by
      @default_file_names = default_file_names.freeze
    end

    # The file an import reads (D14): an explicit path wins; otherwise the
    # first of the default file names that exists in the app root. Raises
    # SourceNotFoundError naming every path tried.
    def locate_source(explicit_path = nil, root: Rails.root)
      candidates = if explicit_path
                     [Pathname(explicit_path)]
                   else
                     default_file_names.map { |name| Pathname(root).join(name) }
                   end
      candidates.find(&:exist?) or
        raise SourceNotFoundError, "No #{checks_name} CSV found. Looked for:\n  #{candidates.join("\n  ")}"
    end

    # What a rake task shows an operator: the file chosen, the result and the
    # sample rejections. Raises like locate_source and #import.
    def import_and_report(explicit_path = nil, output: $stdout)
      path = locate_source(explicit_path)
      output.puts "Importing #{checks_name} from #{path}"

      result = new(path).import
      output.puts "#{checks_name.upcase_first}: #{result.summary}"
      result.rejection_samples.each { |rejection| output.puts "  rejected line #{rejection.line}: #{rejection.reason}" }
      result
    end

    # "inventory checks", "price checks"
    def checks_name
      check_class.model_name.plural.humanize(capitalize: false)
    end
  end

  def initialize(path, batch_size: 5_000, logger: Rails.logger)
    @path = path
    @batch_size = batch_size
    @logger = logger
  end

  # Returns a Result. Raises MissingHeadersError before inserting anything
  # when the file isn't an export of this kind of check, and lets
  # CSV::MalformedCSVError (which rolls the import back) through for a
  # structurally broken file.
  def import
    @rows_read = @inserted = @rejected = 0
    @rejection_samples = []
    @parser = self.class.row_parser_class.new

    self.class.check_class.transaction { each_batch { |batch| @inserted += insert(batch) } }
    result.tap { |imported| log(imported) }
  end

  private

  def each_batch
    batch = []
    each_row do |row, line|
      attributes = attributes_or_rejection(row, line) or next
      batch << attributes
      next if batch.size < @batch_size

      yield batch
      batch = []
    end
    yield batch if batch.any?
  end

  def each_row
    CSV.open(@path, encoding: "bom|utf-8", headers: true, return_headers: true) do |csv|
      verify_headers(csv.shift)
      csv.each do |row|
        @rows_read += 1
        yield row, csv.lineno
      end
    end
  end

  def verify_headers(header_row)
    missing = self.class.row_parser_class.required_headers - Array(header_row&.headers)
    return if missing.empty?

    raise MissingHeadersError, "#{@path} is missing required headers: #{missing.join(', ')}"
  end

  def attributes_or_rejection(row, line)
    @parser.attributes_for(row)
  rescue CsvCheckRowParser::RowRejected => rejection
    @rejected += 1
    if @rejection_samples.size < rejection_sample_limit
      @rejection_samples << Rejection.new(line:, reason: rejection.message)
    end
    nil
  end

  # Returns how many rows were new. Postgres also skips a row that repeats an
  # earlier row of the same statement, so in-batch duplicates are not counted.
  def insert(batch)
    self.class.check_class.insert_all(batch, unique_by: self.class.unique_index, returning: :id).length
  end

  # Every readable row was either inserted or turned away by the unique index,
  # whether it repeated a stored check or an earlier row of this file.
  def result
    Result.new(rows_read: @rows_read, inserted: @inserted, duplicates: @rows_read - @rejected - @inserted,
               rejected: @rejected, rejection_samples: @rejection_samples.freeze)
  end

  def rejection_sample_limit = 5

  def log(imported)
    @logger.info("[#{self.class.name}] #{@path}: #{imported.summary}")
    imported.rejection_samples.each do |rejection|
      @logger.warn("[#{self.class.name}] rejected line #{rejection.line}: #{rejection.reason}")
    end
  end
end
