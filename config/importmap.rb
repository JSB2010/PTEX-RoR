pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"

# Third-party libraries
pin "bootstrap", to: "bootstrap.min.js", preload: true
pin "@popperjs/core", to: "popper.js", preload: true

# Metrics Dashboard
pin "metrics-dashboard", to: "controllers/metrics_dashboard_controller.js"

# Explicitly pin the admin credentials controller
pin "controllers/admin_credentials_controller", preload: true