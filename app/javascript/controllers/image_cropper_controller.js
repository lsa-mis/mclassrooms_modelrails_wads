import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "slider", "liveRegion"]
  static values = { aspectRatio: { type: Number, default: 1 } }

  connect() {
    this._initialized = false
    this._baseTransform = null

    // Defer initialization if element is hidden (v2 produces 0x0 selection on hidden elements)
    if (this.element.closest("[hidden]")) {
      this._observeVisibility()
    } else {
      this._deferredInit()
    }
  }

  disconnect() {
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }
    if (this._cropper) {
      this._cropper.getCropperCanvas()?.remove()
      this._cropper = null
    }
    this._initialized = false
  }

  // Public: load a new image (called by identity_picker_controller)
  loadImage(src) {
    if (this._cropper) {
      this._cropper.getCropperCanvas()?.remove()
      this._cropper = null
      this._initialized = false
    }

    const img = this.containerTarget.querySelector("img")
    if (img) {
      img.src = src
      this._deferredInit()
    }
  }

  // Public: export cropped region as blob
  async exportCrop() {
    if (!this._cropper) return null

    const selection = this._cropper.getCropperSelection()
    if (!selection) return null

    const canvas = await selection.$toCanvas({
      beforeDraw(context) {
        context.fillStyle = "#ffffff"
        context.fillRect(0, 0, context.canvas.width, context.canvas.height)
      }
    })

    return new Promise((resolve) => {
      canvas.toBlob((blob) => {
        const coords = this._getCropCoordinates()
        resolve({ blob, coordinates: coords })
      }, "image/png")
    })
  }

  // Zoom slider handler
  handleSlider() {
    if (!this._cropper || !this._baseTransform) return

    const value = parseInt(this.sliderTarget.value, 10)
    const image = this._cropper.getCropperImage()
    const baseScale = this._baseTransform[0]
    const targetScale = baseScale * Math.pow(3, value / 100)

    const newTransform = [...this._baseTransform]
    newTransform[0] = targetScale
    newTransform[3] = targetScale
    image.$setTransform(newTransform)

    // $setTransform doesn't fire actionend — dispatch manually for live preview
    const canvas = this._cropper.getCropperCanvas()
    canvas.dispatchEvent(new CustomEvent("actionend", { bubbles: true }))

    this._announceZoom(value)
  }

  // Keyboard shortcuts
  handleKeydown(event) {
    if (!this._cropper) return

    const selection = this._cropper.getCropperSelection()
    const image = this._cropper.getCropperImage()
    if (!selection || !image) return

    const step = event.shiftKey ? 10 : 1

    switch (event.key) {
      case "ArrowUp":
        event.preventDefault()
        selection.$move(0, -step)
        break
      case "ArrowDown":
        event.preventDefault()
        selection.$move(0, step)
        break
      case "ArrowLeft":
        event.preventDefault()
        selection.$move(-step, 0)
        break
      case "ArrowRight":
        event.preventDefault()
        selection.$move(step, 0)
        break
      case "+":
      case "=":
        event.preventDefault()
        this._adjustZoom(5)
        break
      case "-":
        event.preventDefault()
        this._adjustZoom(-5)
        break
    }
  }

  // Private

  _observeVisibility() {
    const hiddenParent = this.element.closest("[hidden]")
    if (!hiddenParent) return

    this._observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "attributes" && mutation.attributeName === "hidden") {
          if (!hiddenParent.hidden) {
            this._observer.disconnect()
            this._observer = null
            this._deferredInit()
            break
          }
        }
      }
    })

    this._observer.observe(hiddenParent, { attributes: true, attributeFilter: ["hidden"] })
  }

  _deferredInit() {
    // Double rAF ensures browser has reflowed after visibility change
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this._initCropper()
      })
    })
  }

  async _initCropper() {
    if (this._initialized) return

    const { default: Cropper } = await import("cropperjs")

    const img = this.containerTarget.querySelector("img")
    if (!img) return

    this._cropper = new Cropper(img, {
      template: this._cropperTemplate()
    })

    // Wait for image to be ready, then capture baseline transform
    const canvas = this._cropper.getCropperCanvas()
    if (canvas) {
      canvas.addEventListener("actionend", () => {
        this.dispatch("cropChanged")
      })
    }

    // Capture base transform after image loads
    const image = this._cropper.getCropperImage()
    if (image) {
      image.addEventListener("transform", () => {
        if (!this._baseTransform) {
          this._baseTransform = image.$getTransform()
        }
      }, { once: true })
    }

    // Enforce selection bounds
    const selection = this._cropper.getCropperSelection()
    if (selection) {
      selection.addEventListener("change", (event) => {
        this._enforceBounds(event, selection)
      })
    }

    this._initialized = true
    this._announceReady()
  }

  _cropperTemplate() {
    return `
      <cropper-canvas background>
        <cropper-image
          initial-center-size="contain"
          rotatable scalable skewable translatable
        ></cropper-image>
        <cropper-shade hidden></cropper-shade>
        <cropper-handle action="move" plain></cropper-handle>
        <cropper-selection movable resizable outlined
          aspect-ratio="${this.aspectRatioValue}"
          initial-coverage="0.8">
          <cropper-handle action="move"
            style="width:100%;height:100%;background:transparent">
          </cropper-handle>
          <cropper-handle action="resize-top-left"></cropper-handle>
          <cropper-handle action="resize-top-right"></cropper-handle>
          <cropper-handle action="resize-bottom-left"></cropper-handle>
          <cropper-handle action="resize-bottom-right"></cropper-handle>
        </cropper-selection>
      </cropper-canvas>
    `
  }

  _enforceBounds(event, selection) {
    const canvas = this._cropper?.getCropperCanvas()
    if (!canvas) return

    const canvasRect = canvas.getBoundingClientRect()
    const { x, y, width, height } = event.detail

    if (x < 0 || y < 0 ||
        x + width > canvasRect.width ||
        y + height > canvasRect.height) {
      event.preventDefault()
    }
  }

  _getCropCoordinates() {
    const selection = this._cropper?.getCropperSelection()
    if (!selection) return null

    const { x, y, width, height } = selection
    return {
      x: Math.round(x),
      y: Math.round(y),
      w: Math.round(width),
      h: Math.round(height)
    }
  }

  _adjustZoom(delta) {
    if (!this.hasSliderTarget) return
    const current = parseInt(this.sliderTarget.value, 10)
    this.sliderTarget.value = Math.max(0, Math.min(100, current + delta))
    this.handleSlider()
  }

  _announceZoom(value) {
    if (!this.hasLiveRegionTarget) return
    const percent = Math.round(100 + value * 2)
    this.liveRegionTarget.textContent = `Zoom ${percent}%`
  }

  _announceReady() {
    if (!this.hasLiveRegionTarget) return
    this.liveRegionTarget.textContent = "Image loaded. Use arrow keys to move selection, plus and minus to zoom."
  }
}
