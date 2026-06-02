# frozen_string_literal: true

module UI
  # # Avatar
  #
  # A circular avatar that renders either a photo (`<img>`) or a hue-tinted
  # initials `<span>`, at five standard sizes. Decorative by default (`aria-hidden`).
  #
  # **In most views, render a user's avatar via the helper:**
  # `avatar_for(user, size: :md)`
  # The helper resolves the avatar source (uploaded photo → Gravatar → initials),
  # applies the user's `primary_color` hue, and sets the correct ARIA attributes.
  # Use `ui :avatar` directly for non-user or standalone avatars.
  #
  # ## Use when
  # - You need a non-user avatar (e.g. a workspace icon, a placeholder in a demo).
  # - You are rendering a custom photo or initials with an explicit hue outside the
  #   user model.
  #
  # ## Don't use when
  # - You are rendering a `User` record's avatar — call `avatar_for(user, size: :md)`
  #   so Active Storage, Gravatar fallback, and the user's primary color are handled.
  #
  # ## Accessibility contract
  # - **Guarantees:** `rounded-full` sizing per `AVATAR_SIZES`, hue-tinted initials
  #   background, and `aria-hidden="true"` by default (decorative).
  # - **You supply:** an `aria_label:` when the avatar must be announced by assistive
  #   technology — for example, when it is the sole content of an interactive control
  #   such as a button or link. For image avatars, `aria_label:` also sets `alt`.
  class AvatarComponentPreview < ViewComponent::Preview
    include UIHelper

    # Photo avatar: pass `src:` with an image URL. The element renders as `<img>`.
    def image
      ui :avatar, src: "https://i.pravatar.cc/128", size: :lg
    end

    # Initials avatar: pass `fallback:` with the initials string. Uses the default
    # interactive color token.
    def initials
      ui :avatar, fallback: "JD", size: :md
    end

    # Custom hue: `hue:` accepts an OKLCH integer (0–360), tinting the background
    # with `--hue-initials`. Useful for workspace or org avatars.
    def custom_hue
      ui :avatar, fallback: "JD", hue: 280
    end

    # Explore size and initials interactively.
    # @param size select [xs, sm, md, lg, xl]
    # @param fallback text
    def playground(size: :lg, fallback: "VP")
      ui :avatar, fallback: fallback, size: size.to_sym
    end

    # ## Don't — interactive avatar with no accessible label
    #
    # When an avatar is the only content of a button or link, there is no visible text
    # to announce. Pass `aria_label:` to expose the avatar to assistive technology:
    # `ui :avatar, src: url, size: :sm, aria_label: "Open Dave's profile"`.
    # For user avatars, prefer `avatar_for(user, size: :sm)` — it sets the label for you.
    # @label Don't · interactive avatar with no label
    def dont_interactive_no_label
      ui :avatar, src: "https://i.pravatar.cc/128", size: :sm # ✗ wrap in a button? add aria_label:
    end
  end
end
