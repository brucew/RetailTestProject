namespace :inventory_alerts do
  desc "Rebuild every inventory alert from the inventory checks (imports already keep the pairs they touch up to date)"
  task reconcile: :environment do
    result = InventoryAlerts::Reconciler.new.reconcile
    puts "Reconciled every store and product: #{result.summary}"
  end
end
