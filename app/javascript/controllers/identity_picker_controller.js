import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "preview",          // large preview circle
    "sourceField",      // hidden input for avatar_source
    "colorField",       // hidden input for primary_color
    "colorSlider",      // range input for hue
    "colorPanel",       // color picker panel (shown/hidden)
    "colorHex",         // hex display span
    "fileInput",        // hidden file input
    "initialsPreview",  // initials circle in preview
    "photoPreview",     // photo button in preview
    "gravPreview",      // gravatar img in preview
    "cropPreview",      // small circular preview in crop view
    "sourceCards",      // radiogroup container for source cards
    "form",             // the hub form
    "gifWarning"        // warning banner shown when source file is a GIF
  ]

  static values = {
    formUrl: String,
    currentSource: String,
    hasImage: Boolean,
    hubTitle: String,
    cropTitle: String
  }

  connect() {
    this._pendingFile = null
    this._currentMode = "hub"
    this._filePickerOpen = false

    // Intercept Escape and X button when in crop mode —
    // navigate back to hub instead of closing the modal.
    //
    // The modal controller (on the dialog) has its own `cancel` listener
    // that calls close() programmatically. We must intercept the cancel
    // event with capture: true + stopImmediatePropagation to prevent the
    // modal controller's handler from running.
    //
    // We also intercept cancel while the file picker is open: when the
    // user dismisses the OS file dialog (e.g. presses Escape), the browser
    // fires a cancel event on the ancestor <dialog>. We prevent that from
    // closing the whole modal — the user just changed their mind about
    // picking a file and should remain on the hub view.
    this._dialog = this.element.closest("dialog")
    if (this._dialog) {
      this._handleCancel = (event) => {
        if (this._currentMode === "crop") {
          event.preventDefault()
          event.stopImmediatePropagation()
          this.backToHub()
        } else if (this._filePickerOpen) {
          // File picker was dismissed without selecting a file — stay in hub
          event.preventDefault()
          event.stopImmediatePropagation()
          this._filePickerOpen = false
        }
      }
      this._dialog.addEventListener("cancel", this._handleCancel, true)

      // Intercept the X (close) button in the modal header
      const closeBtn = this._dialog.querySelector("[data-action='click->modal#close']")
      if (closeBtn) {
        this._handleCloseClick = (event) => {
          if (this._currentMode === "crop") {
            event.preventDefault()
            event.stopImmediatePropagation()
            this.backToHub()
          }
        }
        closeBtn.addEventListener("click", this._handleCloseClick, true)
      }
    }
  }

  disconnect() {
    if (this._dialog && this._handleCancel) {
      this._dialog.removeEventListener("cancel", this._handleCancel, true)
    }
    if (this._dialog) {
      const closeBtn = this._dialog.querySelector("[data-action='click->modal#close']")
      if (closeBtn && this._handleCloseClick) {
        closeBtn.removeEventListener("click", this._handleCloseClick, true)
      }
    }
  }

  // Source card selection via click (on the <label>)
  selectSource(event) {
    // Labels forward clicks to their input, causing duplicate events.
    // Only handle the original click on the label, not the forwarded one.
    if (event.target.tagName === "INPUT") return

    const source = event.params.source
    if (!source) return

    this._selectSourceByValue(source)
    this._autoOpenForSource(source)
  }

  // Radio change — fires when keyboard user navigates with arrow keys
  // inside the radiogroup. The label's click handler doesn't fire for
  // keyboard selection, so we handle the change event separately.
  // Note: we deliberately DO NOT auto-open file picker / crop view on
  // keyboard change — keyboard users should be able to browse sources
  // with arrow keys without being yanked into another view.
  handleSourceChange(event) {
    const source = event.target.value
    if (!source) return

    this._selectSourceByValue(source)
  }

  _selectSourceByValue(source) {
    this.currentSourceValue = source
    this.sourceFieldTarget.value = source
    this._updatePreview()
    this._updateContextualControls()
    this._updateCardStyles()
  }

  // Click on the Photo source card:
  // - No image → open file picker (must upload to use this source)
  // - Has image → open crop view to adjust
  // Use setTimeout to let the current click event finish first
  // (prevents browser conflicts with programmatic file input clicks)
  _autoOpenForSource(source) {
    if (source !== "upload") return

    setTimeout(() => {
      if (this.hasImageValue) {
        this.openCrop()
      } else {
        this.openFilePicker()
      }
    }, 0)
  }

  // Click on photo preview → open crop view (re-crop existing image)
  openCrop() {
    if (this.currentSourceValue !== "upload" || !this.hasImageValue) return
    this._switchMode("crop")

    // Initialize cropper with the existing image (already visible in container)
    const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
    if (cropperEl) {
      const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
      if (cropper) cropper.initExisting()
    }
  }

  // Open native file picker
  openFilePicker() {
    this._filePickerOpen = true
    this.fileInputTarget.click()
  }

  // File selected from native picker
  handleFileSelected(event) {
    this._filePickerOpen = false
    const file = event.target.files[0]
    if (!file) return

    // Client-side validation
    const validTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]
    if (!validTypes.includes(file.type)) {
      this._announce("Invalid file type. Please select a PNG, JPEG, GIF, or WebP image.")
      return
    }
    if (file.size > 5 * 1024 * 1024) {
      this._announce("File is too large. Maximum size is 5 MB.")
      return
    }

    // Release any prior pending file/URL before creating a new one
    this._releasePendingFile()

    this._pendingFile = file
    this._pendingObjectUrl = URL.createObjectURL(file)
    const objectUrl = this._pendingObjectUrl

    // GIFs get rendered as a single static frame by canvas — warn the user.
    this._toggleGifWarning(file.type === "image/gif")

    // Switch to crop view FIRST so the container is visible,
    // THEN load the image (Cropper.js v2 needs a visible container)
    this._switchMode("crop")

    const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
    if (cropperEl) {
      const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
      if (cropper) {
        cropper.loadImage(objectUrl)
      }
    }

    // Reset file input so same file can be re-selected
    event.target.value = ""
  }

  // "Save crop" button clicked
  async saveCrop() {
    // In-flight guard — prevent double-click duplicate uploads
    if (this._saving) return
    this._saving = true

    try {
      const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
      if (!cropperEl) return

      const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
      if (!cropper) return

      const result = await cropper.exportCrop()
      if (!result) return

      const { blob, coordinates } = result

      const formData = new FormData()
      formData.append("avatar", blob, "cropped-avatar.png")

      if (this._pendingFile) {
        formData.append("avatar_original", this._pendingFile)
      }

      formData.append("avatar_source", "upload")
      formData.append("crop_coordinates", JSON.stringify(coordinates))

      this._appendCsrfToken(formData)

      const response = await fetch(this.formUrlValue, {
        method: "PATCH",
        headers: { "Accept": "text/vnd.turbo-stream.html" },
        body: formData
      })

      // Server validation failed — render error turbo stream, stay on crop view
      if (response.status === 422) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
        this._announce("Upload failed. Please try again.")
        return
      }

      // Any other failure — show error, stay on crop view
      if (!response.ok) {
        this._announce("Upload failed. Please try again.")
        return
      }

      // Success — render turbo stream, clean up, return to hub
      const html = await response.text()
      Turbo.renderStreamMessage(html)

      this._releasePendingFile()

      this.hasImageValue = true
      this.currentSourceValue = "upload"
      this.sourceFieldTarget.value = "upload"

      if (this.hasPhotoPreviewTarget) {
        const previewImg = this.photoPreviewTarget.querySelector("img")
        if (previewImg && this.hasCropPreviewTarget && this.cropPreviewTarget.src) {
          previewImg.src = this.cropPreviewTarget.src
        }
      }

      this._switchMode("hub")
      this._updatePreview()
      this._updateContextualControls()
      this._updateCardStyles()
    } catch (error) {
      console.error("saveCrop failed:", error)
      this._announce("Upload failed. Please check your connection and try again.")
    } finally {
      this._saving = false
    }
  }

  // "Remove photo" from crop view — persists immediately to the server
  async removePhoto() {
    // In-flight guard (shared with saveCrop)
    if (this._saving) return
    this._saving = true

    try {
      const formData = new FormData()
      formData.append("avatar_source", "initials")

      this._appendCsrfToken(formData)

      const response = await fetch(this.formUrlValue, {
        method: "PATCH",
        headers: { "Accept": "text/vnd.turbo-stream.html" },
        body: formData
      })

      if (response.status === 422) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
        this._announce("Could not remove photo. Please try again.")
        return
      }

      if (!response.ok) {
        this._announce("Could not remove photo. Please try again.")
        return
      }

      const html = await response.text()
      Turbo.renderStreamMessage(html)

      this._releasePendingFile()
      this.hasImageValue = false
      this.currentSourceValue = "initials"
      this.sourceFieldTarget.value = "initials"
      this._switchMode("hub")
      this._updatePreview()
      this._updateContextualControls()
      this._updateCardStyles()
    } catch (error) {
      console.error("removePhoto failed:", error)
      this._announce("Could not remove photo. Please check your connection and try again.")
    } finally {
      this._saving = false
    }
  }

  // "Back to hub" from crop view
  backToHub() {
    this._releasePendingFile()
    this._switchMode("hub")
  }

  // Reset crop to initial state
  resetCrop() {
    const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
    if (!cropperEl) return

    const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
    if (cropper) cropper.reset()
  }

  // Color slider changed
  handleColorChange() {
    const hue = parseInt(this.colorSliderTarget.value, 10)
    this.colorFieldTarget.value = hue

    // Update preview
    if (this.hasInitialsPreviewTarget) {
      this.initialsPreviewTarget.style.backgroundColor = `oklch(0.45 0.2 ${hue})`
    }

    // Update hex display
    if (this.hasColorHexTarget) {
      this.colorHexTarget.textContent = this._hueToColorName(hue)
    }

    this._announceColor(hue)
  }

  // Crop view dispatches this when crop changes (for live preview)
  updateCropPreview(event) {
    if (!this.hasCropPreviewTarget) return

    const cropperEl = this.element.querySelector("[data-controller='image-cropper']")
    if (!cropperEl) return

    const cropper = this.application.getControllerForElementAndIdentifier(cropperEl, "image-cropper")
    if (!cropper?._cropper) return

    const selection = cropper._cropper.getCropperSelection()
    if (!selection) return

    selection.$toCanvas({ width: 48, height: 48 }).then((canvas) => {
      this.cropPreviewTarget.src = canvas.toDataURL()
    }).catch(() => {})
  }

  // Private

  _switchMode(mode) {
    // Remember where focus was so we can restore it when returning to hub
    if (mode === "crop" && this._currentMode !== "crop") {
      this._previouslyFocused = document.activeElement
    }

    // Any view transition closes the "file picker is open" window. Keeps the
    // flag self-healing against any future flow that opens the picker from a
    // different mode without going through handleFileSelected or backToHub.
    this._filePickerOpen = false

    this._currentMode = mode
    const ctrl = this.application.getControllerForElementAndIdentifier(this.element, "mode-switch")
    if (ctrl) ctrl.modeValue = mode
    this._toggleModalSize(mode)
    this._updateModalTitle(mode)
    this._manageFocus(mode)
  }

  _manageFocus(mode) {
    // Wait a tick for the mode-switch to unhide the new section
    requestAnimationFrame(() => {
      if (mode === "crop") {
        // Focus the crop area so arrow keys immediately move the selection
        const container = this.element.querySelector("[data-image-cropper-target='container']")
        container?.focus()
      } else if (mode === "hub") {
        // Restore focus to what was focused before entering crop,
        // or fall back to the currently-selected source card's radio
        if (this._previouslyFocused && this.element.contains(this._previouslyFocused)) {
          this._previouslyFocused.focus()
        } else {
          const selectedCard = this.element.querySelector(`[data-source='${this.currentSourceValue}']`)
          const radio = selectedCard?.querySelector("input[type='radio']")
          radio?.focus()
        }
        this._previouslyFocused = null
      }
    })
  }

  _updatePreview() {
    // Show/hide the correct preview element based on source
    if (this.hasInitialsPreviewTarget) {
      this.initialsPreviewTarget.hidden = this.currentSourceValue !== "initials"
    }
    if (this.hasPhotoPreviewTarget) {
      this.photoPreviewTarget.hidden = this.currentSourceValue !== "upload"
    }
    if (this.hasGravPreviewTarget) {
      this.gravPreviewTarget.hidden = this.currentSourceValue !== "gravatar"
    }
  }

  _updateContextualControls() {
    if (this.hasColorPanelTarget) {
      this.colorPanelTarget.hidden = this.currentSourceValue !== "initials"
    }
  }

  _updateCardStyles() {
    if (!this.hasSourceCardsTarget) return

    const cards = this.sourceCardsTarget.querySelectorAll("[data-source]")
    cards.forEach((card) => {
      const isSelected = card.dataset.source === this.currentSourceValue
      const radio = card.querySelector("input[type='radio']")
      if (radio) radio.checked = isSelected

      if (isSelected) {
        card.classList.remove("border-border")
        card.classList.add("border-interactive", "bg-interactive/5")
      } else {
        card.classList.remove("border-interactive", "bg-interactive/5")
        card.classList.add("border-border")
      }
    })
  }

  _hueToColorName(hue) {
    if (hue < 30) return "Red"
    if (hue < 60) return "Orange"
    if (hue < 90) return "Yellow"
    if (hue < 150) return "Green"
    if (hue < 210) return "Cyan"
    if (hue < 270) return "Blue"
    if (hue < 330) return "Purple"
    return "Pink"
  }

  _announceColor(hue) {
    const liveRegion = this.element.querySelector("[aria-live='polite']")
    if (liveRegion) {
      liveRegion.textContent = `Color: ${this._hueToColorName(hue)}`
    }
  }

  _announce(message) {
    const liveRegion = this.element.querySelector("[aria-live='polite']")
    if (liveRegion) {
      liveRegion.textContent = message
    }
  }

  _releasePendingFile() {
    if (this._pendingObjectUrl) {
      URL.revokeObjectURL(this._pendingObjectUrl)
      this._pendingObjectUrl = null
    }
    this._pendingFile = null
    // Any time we release the pending file, any GIF warning no longer applies.
    this._toggleGifWarning(false)
  }

  _toggleGifWarning(show) {
    if (this.hasGifWarningTarget) {
      this.gifWarningTarget.hidden = !show
    }
  }

  // Append the CSRF token from <meta name="csrf-token"> to FormData.
  // If the meta tag is missing, log a warning — without the token, Rails
  // will reject the request with 422 InvalidAuthenticityToken and the
  // user will see a generic error. The warning helps developers catch
  // layout regressions that accidentally remove csrf_meta_tags.
  _appendCsrfToken(formData) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) {
      formData.append("authenticity_token", csrfToken)
    } else {
      console.warn(
        "[identity-picker] CSRF token meta tag not found — request will likely fail. " +
        "Ensure <%= csrf_meta_tags %> is in the layout."
      )
    }
  }

  _toggleModalSize(mode) {
    const panel = this.element.closest("[data-modal-target='panel']")
    if (!panel) return

    if (mode === "crop") {
      panel.classList.remove("max-w-2xl")
      panel.classList.add("max-w-4xl")
    } else {
      panel.classList.remove("max-w-4xl")
      panel.classList.add("max-w-2xl")
    }
  }

  _updateModalTitle(mode) {
    if (!this._dialog) return
    const titleEl = this._dialog.querySelector("[id$='-title']")
    if (!titleEl) return

    titleEl.textContent = mode === "crop" ? this.cropTitleValue : this.hubTitleValue
  }
}
