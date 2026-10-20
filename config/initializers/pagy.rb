# Pagy 9.x configuration: https://ddnexus.github.io/pagy-9/docs/api/pagy/
# (Pagy 43+ needs Ruby 3.3; this app runs on 3.2.)

# Long check histories are shown 50 rows at a time (A10).
Pagy::DEFAULT[:limit] = 50

# A page past the last one names a page that does not exist, and a page of 0
# or "abc" is a malformed request. Without this both would surface as 500s.
ActionDispatch::ExceptionWrapper.rescue_responses.merge!(
  "Pagy::OverflowError" => :not_found,
  "Pagy::VariableError" => :bad_request
)

Pagy::DEFAULT.freeze
