import { Controller } from "@hotwired/stimulus"

const MODES = ["normal", "blur", "grayscale", "deuteranopia", "low_contrast", "cataract"]
const STORAGE_KEY = "a11y_sim_mode"
const BODY_CLASS_PREFIX = "a11y-sim-"

export default class extends Controller {
  static targets = ["menu", "trigger", "triggerIcon", "triggerLabel", "item", "announcer"]
  static values = { announcementTemplate: { type: String, default: "Filter: %{mode}" } }

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    this.handleGlobalKeydown = this.handleGlobalKeydown.bind(this)

    const stored = this.readStoredMode()
    this.applyMode(stored)

    document.addEventListener("keydown", this.handleGlobalKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick, true)
    document.removeEventListener("keydown", this.handleGlobalKeydown)
  }

  toggle(event) {
    if (event) event.preventDefault()
    this.isOpen() ? this.closeMenu() : this.openMenu()
  }

  select(event) {
    const mode = event.currentTarget.dataset.mode
    if (!MODES.includes(mode)) return
    this.applyMode(mode)
    this.closeMenu()
  }

  openMenu() {
    this.menuTarget.classList.remove("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.handleOutsideClick, true)
    const activeItem = this.activeItem() || this.itemTargets[0]
    activeItem?.focus()
  }

  closeMenu() {
    this.menuTarget.classList.add("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.handleOutsideClick, true)
    this.triggerTarget.focus()
  }

  applyMode(mode) {
    const normalized = MODES.includes(mode) ? mode : "normal"

    MODES.forEach(m => {
      if (m === "normal") return
      document.body.classList.toggle(`${BODY_CLASS_PREFIX}${m}`, m === normalized)
    })

    try {
      if (normalized === "normal") {
        window.localStorage.removeItem(STORAGE_KEY)
      } else {
        window.localStorage.setItem(STORAGE_KEY, normalized)
      }
    } catch (_error) {
      // localStorage can be unavailable (Safari private browsing, quota full).
      // The filter still applies in-memory for this page.
    }

    this.updateTrigger(normalized)
    this.updateMenuSelection(normalized)
    this.announce(normalized)
  }

  announce(mode) {
    if (!this.hasAnnouncerTarget) return
    const label = this.labelFor(mode)
    this.announcerTarget.textContent = this.announcementTemplateValue.replace("%{mode}", label)
  }

  updateTrigger(mode) {
    this.itemTargets.forEach(item => {
      const iconHost = item.querySelector("[data-a11y-sim-icon]")
      if (item.dataset.mode === mode && iconHost && this.hasTriggerIconTarget) {
        this.triggerIconTarget.innerHTML = iconHost.innerHTML
      }
    })
    if (this.hasTriggerLabelTarget) {
      this.triggerLabelTarget.textContent = this.labelFor(mode)
    }
  }

  updateMenuSelection(mode) {
    this.itemTargets.forEach(item => {
      const active = item.dataset.mode === mode
      item.dataset.active = active ? "true" : "false"
      item.setAttribute("aria-checked", active ? "true" : "false")
    })
  }

  labelFor(mode) {
    const item = this.itemTargets.find(i => i.dataset.mode === mode)
    return item?.querySelector("[data-a11y-sim-label]")?.textContent?.trim() ?? mode
  }

  activeItem() {
    return this.itemTargets.find(i => i.dataset.active === "true")
  }

  isOpen() {
    return !this.menuTarget.classList.contains("hidden")
  }

  readStoredMode() {
    try {
      const stored = window.localStorage.getItem(STORAGE_KEY)
      return MODES.includes(stored) ? stored : "normal"
    } catch (_error) {
      return "normal"
    }
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.closeMenu()
  }

  handleGlobalKeydown(event) {
    if (this.isShortcutToggle(event)) {
      event.preventDefault()
      this.toggle()
      return
    }

    if (!this.isOpen()) return

    switch (event.key) {
      case "Escape":
        event.preventDefault()
        this.closeMenu()
        return
      case "Tab":
        this.closeMenu()
        return
      case "ArrowDown":
        event.preventDefault()
        this.focusItemByOffset(1)
        return
      case "ArrowUp":
        event.preventDefault()
        this.focusItemByOffset(-1)
        return
      case "Home":
        event.preventDefault()
        this.itemTargets[0]?.focus()
        return
      case "End":
        event.preventDefault()
        this.itemTargets[this.itemTargets.length - 1]?.focus()
        return
    }

    if (event.key >= "0" && event.key <= "5") {
      const index = parseInt(event.key, 10)
      const mode = MODES[index]
      if (mode) {
        event.preventDefault()
        this.applyMode(mode)
        this.closeMenu()
      }
    }
  }

  focusItemByOffset(offset) {
    const items = this.itemTargets
    if (items.length === 0) return
    const currentIndex = items.indexOf(document.activeElement)
    const nextIndex = currentIndex === -1
      ? (offset > 0 ? 0 : items.length - 1)
      : (currentIndex + offset + items.length) % items.length
    items[nextIndex]?.focus()
  }

  isShortcutToggle(event) {
    return (event.metaKey || event.ctrlKey) && event.shiftKey && event.key.toLowerCase() === "a"
  }
}
