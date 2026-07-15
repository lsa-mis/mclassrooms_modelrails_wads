module FormDraftHelpers
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
