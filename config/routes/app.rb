# Fork-owned: your product's routes live here. Upstream (modelrails_base)
# freezes this file after creation — add and rewrite routes freely in a fork
# without merge conflicts on config/routes.rb. See /docs/forking.

root "pages#home"
get "about", to: "pages#about"
get "privacy", to: "pages#privacy"
get "contact", to: "pages#contact"
