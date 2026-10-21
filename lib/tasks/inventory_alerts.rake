namespace :inventory_alerts do
  desc "Rebuild every inventory alert from the inventory checks (an import already reconciles every pair in its file)"
  task reconcile: :environment do
    result = InventoryAlerts::Reconciler.new.reconcile
    puts "Reconciled every store and product: #{result.summary}"
  end
end
