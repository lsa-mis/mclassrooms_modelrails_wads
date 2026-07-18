# config/routes/legacy.rb — D18 (Brief §5.9): retired Classroom Database URLs,
# kept alive after cutover so old bookmarks, registrar links, and deep links
# don't 404. Loaded via `draw(:legacy)` from the fork-owned config/routes/app.rb.
# The `toggle_visibile` misspelling is intentional — it matches the real legacy URL.
get "classrooms/:facility_code", to: "legacy_redirects#room", as: :legacy_classroom
get "classrooms",                to: "legacy_redirects#classrooms_index", as: :legacy_classrooms
get "legacy_crdb",               to: "legacy_redirects#legacy_crdb", as: :legacy_crdb
get "toggle_visibile/:id",       to: "legacy_redirects#toggle_visibility", as: :legacy_toggle_visibility
