import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"

export default class extends Controller {
  static targets = ["image", "preview", "x", "y", "w", "h", "slider", "liveRegion", "dropZone"]
  static values = {
    aspectRatio: { type: Number, default: 1 },
    existingCrop: { type: Object, default: {} },
    viewMode: { type: Number, default: 1 }
  }

  #modalOpenedHandler = null

  connect() {
    this.cropper = null

    if (this.imageTarget.complete && this.imageTarget.naturalWidth > 0) {
      this.#initCropper()
    } else {
      this.imageTarget.addEventListener("load", () => this.#initCropper(), { once: true })
    }

    // Listen for modal:opened in case we're inside a closed dialog
    this.#modalOpenedHandler = () => {
      if (!this.cropper) this.#initCropper()
    }
    document.addEventListener("modal:opened", this.#modalOpenedHandler)
  }

  disconnect() {
    document.removeEventListener("modal:opened", this.#modalOpenedHandler)
    if (this.cropper) {
      this.cropper.destroy()
      this.cropper = null
    }
  }

  save() {
    if (!this.cropper) return
    const data = this.cropper.getData(true)
    this.xTarget.value = data.x
    this.yTarget.value = data.y
    this.wTarget.value = data.width
    this.hTarget.value = data.height
  }

  handleSlider(event) {
    if (!this.cropper) return
    const imageData = this.cropper.getImageData()
    const minZoom = imageData.width / imageData.naturalWidth
    const maxZoom = minZoom * 5
    const value = parseFloat(event.target.value)
    const ratio = minZoom + (maxZoom - minZoom) * (value / 100)
    this.cropper.zoomTo(ratio)
  }

  handleKeydown(event) {
    if (!this.cropper) return
    const step = event.shiftKey ? 10 : 1
    const actions = {
      ArrowLeft: () => this.cropper.move(-step, 0),
      ArrowRight: () => this.cropper.move(step, 0),
      ArrowUp: () => this.cropper.move(0, -step),
      ArrowDown: () => this.cropper.move(0, step),
      "+": () => this.cropper.zoom(0.1),
      "=": () => this.cropper.zoom(0.1),
      "-": () => this.cropper.zoom(-0.1)
    }
    const action = actions[event.key]
    if (action) {
      event.preventDefault()
      action()
    }
  }

  reset() {
    if (!this.cropper) return
    this.cropper.reset()
    this.#syncSlider()
  }

  // Drop-to-upload: when a file is dropped on the crop viewport,
  // find the upload form in the same modal and submit the file
  handleDropUpload(event) {
    event.preventDefault()
    event.stopPropagation()
    this.#clearDropHighlight()

    const files = event.dataTransfer?.files
    if (!files?.length) return

    const file = files[0]
    const accepted = ["image/png", "image/jpeg", "image/gif", "image/webp"]
    if (!accepted.includes(file.type)) return

    // Find the upload form's file input in the same modal or page
    const container = this.element.closest("[data-controller~='modal']") ||
                      this.element.closest("[data-controller~='mode-switch']") ||
                      document.body
    const fileInput = container.querySelector("input[type='file'][accept*='image']")
    const form = fileInput?.closest("form")

    if (fileInput && form) {
      const dt = new DataTransfer()
      dt.items.add(file)
      fileInput.files = dt.files

      // If there's a mode-switch, switch to upload mode first
      const modeSwitch = container.querySelector("[data-controller~='mode-switch']") ||
                          container.closest("[data-controller~='mode-switch']")
      if (modeSwitch) {
        modeSwitch.dataset.modeSwitchModeValue = "upload"
      }

      // Trigger the upload
      fileInput.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  handleDragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.classList.add("ring-2", "ring-interactive-focus", "ring-inset")
    }
  }

  handleDragLeave(event) {
    event.preventDefault()
    event.stopPropagation()
    this.#clearDropHighlight()
  }

  #clearDropHighlight() {
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.classList.remove("ring-2", "ring-interactive-focus", "ring-inset")
    }
  }

  // Private

  #initCropper() {
    // Guard: if inside a closed dialog, defer initialization
    const dialog = this.element.closest("dialog")
    if (dialog && !dialog.open) return

    const previewSelector = this.hasPreviewTarget
      ? `[data-image-cropper-target="preview"]`
      : undefined

    this.cropper = new Cropper(this.imageTarget, {
      aspectRatio: this.aspectRatioValue,
      viewMode: this.viewModeValue,
      dragMode: "move",
      autoCropArea: 1,
      responsive: true,
      restore: false,
      guides: true,
      center: true,
      highlight: false,
      background: true,
      preview: previewSelector,
      ready: () => {
        this.#restoreExistingCrop()
        this.#syncSlider()
        this.#warnIfLargeImage()
      },
      crop: () => {
        this.#syncSlider()
        this.#announceChange()
      }
    })
  }

  #restoreExistingCrop() {
    const crop = this.existingCropValue
    if (crop && crop.x != null && crop.w > 0 && crop.h > 0) {
      this.cropper.setData({
        x: crop.x,
        y: crop.y,
        width: crop.w,
        height: crop.h
      })
    }
  }

  #syncSlider() {
    if (!this.hasSliderTarget || !this.cropper) return
    const imageData = this.cropper.getImageData()
    const currentZoom = imageData.width / imageData.naturalWidth
    const minZoom = this.cropper.getCanvasData().naturalWidth
      ? imageData.width / imageData.naturalWidth
      : 1
    const maxZoom = minZoom * 5
    const pct = ((currentZoom - minZoom) / (maxZoom - minZoom)) * 100
    this.sliderTarget.value = Math.max(0, Math.min(100, pct))
  }

  #announceChange() {
    if (!this.hasLiveRegionTarget || !this.cropper) return
    const data = this.cropper.getData(true)
    this.liveRegionTarget.textContent =
      `Crop area: ${data.width} by ${data.height} pixels at position ${data.x}, ${data.y}`
  }

  #warnIfLargeImage() {
    const img = this.imageTarget
    if (img.naturalWidth > 4096 || img.naturalHeight > 4096) {
      console.warn(
        `image-cropper: Large image detected (${img.naturalWidth}x${img.naturalHeight}). ` +
        `Consider client-side downscaling for better performance on mobile devices.`
      )
    }
  }
}
