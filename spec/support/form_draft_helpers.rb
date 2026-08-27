module FormDraftHelpers
  # The draft controller debounces storage writes 300ms; the encrypted write
  # lands asynchronously some time after the debounce fires.
  AUTOSAVE_DEBOUNCE = 0.3

  # Negative-assertion window (#453): proving NO write happened has no
  # condition to wait on, so wait out the debounce plus a margin, then assert
  # silence. One owned number — the old per-site `sleep 0.5` left a 0.2s
  # margin for the async encrypt+write on a box running ~2.7 concurrent
  # Chromes, a silent false green under load (#857).
  def wait_out_draft_autosave_window
    sleep AUTOSAVE_DEBOUNCE + 0.7
  end

  # Storage writes are debounced 300ms + encrypted asynchronously; poll.
  def wait_for_draft(key_fragment)
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop do
        break if page.evaluate_script(
          "Object.keys(localStorage).some(k => k.includes(#{key_fragment.to_json}) && localStorage.getItem(k) !== null)"
        )
        sleep 0.05
      end
    end
  end

  def draft_storage_key(user, form_key)
    "draft:v1:#{FormDraftKey.scope_for(user)}:#{form_key}"
  end
end

RSpec.configure { |c| c.include FormDraftHelpers, type: :system }
