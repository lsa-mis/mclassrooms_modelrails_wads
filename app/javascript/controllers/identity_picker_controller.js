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
    "form"              // the hub form
  ]

  static values = {
    formUrl: String,
    currentSource: String,
    hasImage: Boolean
  }

  connect() {
    this._pendingFile = null
  }

  // Source card selection
  selectSource(event) {
    // Labels forward clicks to their input, causing duplicate events.
    // Only handle the original click on the label, not the forwarded one.
    if (event.target.tagName === "INPUT") return

    const source = event.params.source
    if (!source) return

    this.currentSourceValue = source
    this.sourceFieldTarget.value = source
    this._updatePreview()
    this._updateContextualControls()
    this._updateCardStyles()

    // Photo + no image → open file picker immediately
    // Use setTimeout to let the current click event finish before
    // opening the file dialog (prevents browser click conflicts)
    if (source === "upload" && !this.hasImageValue) {
      setTimeout(() => this.openFilePicker(), 0)
    }
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
    this.fileInputTarget.click()
  }

  // File selected from native picker
  handleFileSelected(event) {
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

    this._pendingFile = file
    const objectUrl = URL.createObjectURL(file)

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
      this._pendingFile = null
    }

    formData.append("avatar_source", "upload")
    formData.append("crop_coordinates", JSON.stringify(coordinates))

    // Add CSRF token
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) {
      formData.append("authenticity_token", csrfToken)
    }

    const response = await fetch(this.formUrlValue, {
      method: "PATCH",
      headers: { "Accept": "text/vnd.turbo-stream.html" },
      body: formData
    })

    if (response.ok) {
      const html = await response.text()
      Turbo.renderStreamMessage(html)
      this.hasImageValue = true
      this.currentSourceValue = "upload"
      this.sourceFieldTarget.value = "upload"
    }

    // Update the photo preview button with the cropped image
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
  }

  // "Remove photo" from crop view
  removePhoto() {
    this.hasImageValue = false
    this.currentSourceValue = "initials"
    this.sourceFieldTarget.value = "initials"
    this._switchMode("hub")
    this._updatePreview()
    this._updateContextualControls()
  }

  // "Back to hub" from crop view
  backToHub() {
    this._pendingFile = null
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
    // mode-switch is on the same element as identity-picker (data-controller="identity-picker mode-switch")
    // so we can use this.element directly
    const ctrl = this.application.getControllerForElementAndIdentifier(this.element, "mode-switch")
    if (ctrl) ctrl.modeValue = mode
    this._toggleModalSize(mode)
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
}
