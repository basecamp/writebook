# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/request.js", to: "@rails--request.js" # @0.0.9
pin "house", to: "house.min.js"

pin_all_from "app/javascript/actions", under: "actions"
pin "mermaid", to: "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/helpers", under: "helpers"
pin_all_from "app/javascript/lib", under: "lib"
