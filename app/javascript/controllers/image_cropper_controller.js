import { Controller } from "@hotwired/stimulus"

const ALLOWED_TYPES = ["image/png", "image/jpeg", "image/gif", "image/webp"]

export default class extends Controller {
  static targets = ["fileInput", "preview", "cropArea", "uploadArea"]
  static values = {
    aspectRatio: { type: Number, default: 0 },
    maxWidth: { type: Number, default: 1024 },
    maxHeight: { type: Number, default: 1024 },
    maxFileSize: { type: Number, default: 5 }
  }

  async connect() {
    this.cropper = null
    this.CropperClass = null

    try {
      const { default: Cropper } = await import("cropperjs")
      this.CropperClass = Cropper
    } catch (error) {
      console.error("Failed to load Cropper.js:", error)
      this.dispatch("error", {
        detail: { message: this.#errorMessage("cropper_load_failed") },
        prefix: "cropper"
      })
    }
  }

  disconnect() {
    this.#destroyCropper()
  }

  loadImage(event) {
    const file = event.target.files[0]
    if (!file) return

    if (!this.#validateFile(file)) return

    this.currentFilename = file.name

    const reader = new FileReader()
    reader.onload = (e) => {
      this.previewTarget.src = e.target.result
      this.previewTarget.onload = () => {
        this.#showCropArea()
        this.#initCropper()
      }
    }
    reader.readAsDataURL(file)
  }

  crop() {
    if (!this.cropper) return

    let canvas = this.cropper.getCroppedCanvas({
      maxWidth: this.maxWidthValue,
      maxHeight: this.maxHeightValue
    })

    canvas.toBlob((blob) => {
      if (!blob) return

      this.dispatch("complete", {
        detail: { blob, filename: this.currentFilename || "cropped.png" },
        prefix: "cropper"
      })
    }, "image/png")
  }

  cancel() {
    this.#destroyCropper()
    this.#showUploadArea()
    this.fileInputTarget.value = ""
    this.dispatch("cancel", { prefix: "cropper" })
  }

  // Private

  #validateFile(file) {
    if (!ALLOWED_TYPES.includes(file.type)) {
      this.dispatch("error", {
        detail: { message: this.#errorMessage("invalid_type") },
        prefix: "cropper"
      })
      this.fileInputTarget.value = ""
      return false
    }

    const maxBytes = this.maxFileSizeValue * 1024 * 1024
    if (file.size > maxBytes) {
      this.dispatch("error", {
        detail: {
          message: this.#errorMessage("file_too_large", { max_size: this.maxFileSizeValue })
        },
        prefix: "cropper"
      })
      this.fileInputTarget.value = ""
      return false
    }

    return true
  }

  #initCropper() {
    if (!this.CropperClass) {
      // Cropper.js failed to load -- fall back to no-crop upload
      this.dispatch("error", {
        detail: { message: this.#errorMessage("cropper_load_failed") },
        prefix: "cropper"
      })
      return
    }

    this.#destroyCropper()

    this.cropper = new this.CropperClass(this.previewTarget, {
      aspectRatio: this.aspectRatioValue || NaN,
      viewMode: 1,
      autoCropArea: 1,
      responsive: true
    })
  }

  #destroyCropper() {
    if (this.cropper) {
      this.cropper.destroy()
      this.cropper = null
    }
  }

  #showCropArea() {
    this.cropAreaTarget.style.display = "flex"
    this.uploadAreaTarget.style.display = "none"
    this.cropAreaTarget.focus()
  }

  #showUploadArea() {
    this.cropAreaTarget.style.display = "none"
    this.uploadAreaTarget.style.display = ""
    this.fileInputTarget.focus()
  }

  #errorMessage(key, interpolations = {}) {
    // Error messages are embedded as data attributes on the controller element
    // to keep I18n in ERB and out of JS. Fallback to English defaults.
    const defaults = {
      invalid_type: "File type not supported. Please use PNG, JPG, GIF, or WebP.",
      file_too_large: `File is too large. Maximum size is ${interpolations.max_size || this.maxFileSizeValue}MB.`,
      cropper_load_failed: "Image editor could not load. Your image will be uploaded without cropping."
    }

    const dataKey = `errorMessage${key.replace(/(^|_)(\w)/g, (_, __, c) => c.toUpperCase())}`
    return this.element.dataset[dataKey] || defaults[key] || "An error occurred."
  }
}
