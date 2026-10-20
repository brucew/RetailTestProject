# Kept for existing scripts and docs. It holds no import logic of its own:
# it runs each check import in turn (D14).
namespace :tracking_events do
  desc "Import every kind of check from its CSV in the app root (runs inventory_checks:import)"
  task import: %w[inventory_checks:import]
end
