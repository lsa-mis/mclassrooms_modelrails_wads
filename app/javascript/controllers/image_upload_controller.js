import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fileInput", "preview", "previewImage", "uploadZone", "submitButton"]

  selectFile() {
    this.fileInputTarget.click()
  }

  handleFile(event) {
    const file = event.target.files[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = (e) => {
      this.previewImageTarget.src = e.target.result
      this.previewTarget.hidden = false
      this.uploadZoneTarget.hidden = true
      if (this.hasSubmitButtonTarget) this.submitButtonTarget.hidden = false
    }
    reader.readAsDataURL(file)
  }

  chooseAnother() {
    this.fileInputTarget.value = ""
    this.fileInputTarget.click()
  }

  handleDragOver(event) {
    event.preventDefault()
    this.uploadZoneTarget.classList.add("border-interactive-focus")
    this.uploadZoneTarget.classList.remove("border-border")
  }

  handleDragLeave(event) {
    event.preventDefault()
    this.uploadZoneTarget.classList.remove("border-interactive-focus")
    this.uploadZoneTarget.classList.add("border-border")
  }

  handleDrop(event) {
    event.preventDefault()
    this.uploadZoneTarget.classList.remove("border-interactive-focus")
    this.uploadZoneTarget.classList.add("border-border")

    const files = event.dataTransfer?.files
    if (files?.length > 0) {
      const dt = new DataTransfer()
      dt.items.add(files[0])
      this.fileInputTarget.files = dt.files
      this.handleFile({ target: { files: dt.files } })
    }
  }
}
