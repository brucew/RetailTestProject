namespace :inventory_checks do
  desc "Delete exact duplicate inventory checks, keeping the earliest copy of each (DRY_RUN=1 only reports)"
  task remove_duplicates: :environment do
    duplicates = InventoryCheck.exact_duplicates

    if ENV["DRY_RUN"].present?
      puts "Dry run: #{duplicates.count} exact duplicate inventory checks would be deleted."
    else
      puts "Deleted #{duplicates.delete_all} exact duplicate inventory checks."
    end
  end
end
