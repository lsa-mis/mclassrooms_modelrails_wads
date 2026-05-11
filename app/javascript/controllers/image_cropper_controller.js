import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "slider", "liveRegion", "zoomPercent", "dimensionBadge"]
  static values = {
    aspectRatio: { type: Number, default: 1 },
    readyAnnounce: String,
    resetAnnounce: String,
    zoomAnnounce: String
  }

  connect() {
    this._initialized = false
    this._baseTransform = null
    this._cropper = null
  }

  disconnect() {
    this._destroy()
  }

  // Public: load a new image and initialize cropper
  // Called by identity_picker_controller — the ONLY init path.
  // The crop view must be visible before calling this.
  loadImage(src) {
    this._destroy()

    const img = this.containerTarget.querySelector("img")
    if (!img) return

    img.src = src

    // Wait for the image to actually load before initializing Cropper
    img.addEventListener("load", () => {
      this._initCropper()
    }, { once: true })

    // If src is an object URL it may already be cached — force load event
    if (img.complete) {
      this._initCropper()
    }
  }

  // Public: initialize cropper with the existing image (for re-crop flow)
  // Called when user clicks photo preview to re-crop an already-uploaded image.
  initExisting() {
    this._destroy()

    // Double rAF to ensure the container is laid out after becoming visible
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this._initCropper()
      })
    })
  }

  // Public: reset selection and zoom to initial state
  reset() {
    if (!this._cropper) return

    const selection = this._cropper.getCropperSelection()
    if (selection) selection.$reset()

    const image = this._cropper.getCropperImage()
    if (image && this._baseTransform) {
      image.$setTransform(this._baseTransform)
    }

    if (this.hasSliderTarget) {
      this.sliderTarget.value = 0
    }
    this._updateZoomPercent(0)

    this._announceReset()

    setTimeout(() => {
      this.dispatch("cropChanged")
      const sel = this._cropper?.getCropperSelection()
      if (sel) this._updateDimensionBadge(sel)
    }, 50)
  }

  // Public: export cropped region as blob
  async exportCrop() {
    if (!this._cropper) return null

    const selection = this._cropper.getCropperSelection()
    if (!selection) return null

    // Scale output by devicePixelRatio so the exported image is sharp on
    // Retina/HiDPI displays. Without this, a 320×320 CSS-pixel selection
    // exports at 320×320 actual pixels — blurry on a 2× display.
    const dpr = window.devicePixelRatio || 1
    const outputWidth = Math.round(selection.width * dpr)
    const outputHeight = Math.round(selection.height * dpr)

    const canvas = await selection.$toCanvas({
      width: outputWidth,
      height: outputHeight,
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
    this._updateZoomPercent(value)
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

  _destroy() {
    if (this._cropper) {
      this._cropper.getCropperCanvas()?.remove()
      this._cropper = null
    }
    this._initialized = false
    this._baseTransform = null
    // Clear the test-facing ready signal so a subsequent re-init has to
    // re-publish it. Without this, a wait_for_crop_view assertion right
    // after _destroy would pass spuriously against the previous run's
    // attribute. Published on the controller's own element so the test
    // selector `[data-controller~='image-cropper'][data-image-cropper-ready='true']`
    // matches a single element.
    this.element.removeAttribute("data-image-cropper-ready")
  }

  async _initCropper() {
    if (this._initialized) return

    const img = this.containerTarget.querySelector("img")
    if (!img || !img.src) return

    const { default: Cropper } = await import("cropperjs")

    // Guard again after async import — another call may have run
    if (this._initialized) return

    this._cropper = new Cropper(img, {
      template: this._cropperTemplate()
    })

    const canvas = this._cropper.getCropperCanvas()
    if (canvas) {
      canvas.addEventListener("actionend", () => {
        this.dispatch("cropChanged")
      })
    }

    // Capture base transform after image has fully settled into its
    // auto-centered position. The first transform events fire during layout
    // before centering completes — capturing too early gives wrong translate
    // values that cause zoom jumps and broken reset.
    const image = this._cropper.getCropperImage()
    if (image) {
      setTimeout(() => {
        if (!this._baseTransform && this._cropper) {
          const img = this._cropper.getCropperImage()
          if (img) this._baseTransform = img.$getTransform()
        }
      }, 500)
    }

    // Enforce selection bounds
    const selection = this._cropper.getCropperSelection()
    if (selection) {
      selection.addEventListener("change", (event) => {
        this._enforceBounds(event, selection)
        this._updateDimensionBadge(selection)
      })
    }

    this._initialized = true

    // Test-facing ready signal — wait_for_crop_view asserts on this so the
    // test budget is decoupled from the bare cropper-canvas DOM element
    // (which appears earlier, before listeners + base transform are set
    // up). Set on the controller's own element so the test selector
    // `[data-controller~='image-cropper'][data-image-cropper-ready='true']`
    // matches one element. Cleared in _destroy().
    this.element.setAttribute("data-image-cropper-ready", "true")

    // Reset zoom slider
    if (this.hasSliderTarget) {
      this.sliderTarget.value = 0
    }
    this._updateZoomPercent(0)

    this._announceReady()

    // Dispatch initial cropChanged so the preview gets its first frame
    // Delay slightly to let Cropper.js finish laying out the selection
    setTimeout(() => {
      this.dispatch("cropChanged")
    }, 100)
  }

  _cropperTemplate() {
    return `
      <cropper-canvas>
        <cropper-image
          initial-center-size="contain"
          scalable
          translatable
        ></cropper-image>
        <cropper-shade></cropper-shade>
        <cropper-selection movable resizable outlined
          aspect-ratio="${this.aspectRatioValue}"
          initial-coverage="0.8">
          <cropper-handle action="move"
            theme-color="rgba(255, 255, 255, 0.35)">
          </cropper-handle>
          <cropper-handle action="n-resize"></cropper-handle>
          <cropper-handle action="e-resize"></cropper-handle>
          <cropper-handle action="s-resize"></cropper-handle>
          <cropper-handle action="w-resize"></cropper-handle>
          <cropper-handle action="ne-resize"></cropper-handle>
          <cropper-handle action="nw-resize"></cropper-handle>
          <cropper-handle action="se-resize"></cropper-handle>
          <cropper-handle action="sw-resize"></cropper-handle>
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
    const template = this.zoomAnnounceValue || "Zoom %{percent}%"
    this.liveRegionTarget.textContent = template.replace("%{percent}", percent)
  }

  _announceReady() {
    if (!this.hasLiveRegionTarget) return
    this.liveRegionTarget.textContent = this.readyAnnounceValue || ""
  }

  _announceReset() {
    if (!this.hasLiveRegionTarget) return
    this.liveRegionTarget.textContent = this.resetAnnounceValue || ""
  }

  _updateZoomPercent(sliderValue) {
    if (!this.hasZoomPercentTarget) return
    const percent = Math.round(100 * Math.pow(3, sliderValue / 100))
    this.zoomPercentTarget.textContent = `${percent}%`
  }

  _updateDimensionBadge(selection) {
    if (!this.hasDimensionBadgeTarget) return
    if (!selection) return

    // Show the actual export dimensions (CSS pixels × devicePixelRatio)
    const dpr = window.devicePixelRatio || 1
    const w = Math.round(selection.width * dpr)
    const h = Math.round(selection.height * dpr)
    this.dimensionBadgeTarget.textContent = `${w} × ${h}px`
  }
}
