// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

import "lexxy"

import "markdowndocs"

// Wires Active Storage direct upload app-wide (MiClassrooms Phase 4 Task 11):
// intercepts the `submit` event on any form containing an
// `input[type=file][data-direct-upload-url]`, uploads each selected file
// straight to storage, then replaces the input with hidden `signed_id`
// field(s) before the form's real submission proceeds. The admin
// bulk-upload flow (app/views/admin/bulk_uploads/new.html.erb) depends on
// this — its two-step review flow re-POSTs SIGNED BLOB IDS across requests,
// which only exist once a blob has been direct-uploaded.
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()
