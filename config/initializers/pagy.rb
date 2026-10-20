# Pagy 9.x configuration: https://ddnexus.github.io/pagy-9/docs/api/pagy/
# (Pagy 43+ needs Ruby 3.3; this app runs on 3.2.)

# Long check histories are shown 50 rows at a time (A10).
Pagy::DEFAULT[:limit] = 50

Pagy::DEFAULT.freeze
