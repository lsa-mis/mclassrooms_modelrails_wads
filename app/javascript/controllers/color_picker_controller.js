import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["colorInput", "textInput", "preview", "swatch"]

  connect() {
    this.syncFromText()
    this.highlightSelected()
  }

  select(event) {
    const color = event.currentTarget.dataset.color
    this.setValue(color)
  }

  updateFromColor() {
    this.setValue(this.colorInputTarget.value)
  }

  updateFromText() {
    this.setValue(this.textInputTarget.value)
  }

  setValue(color) {
    this.colorInputTarget.value = color
    this.textInputTarget.value = color
    this.updatePreview()
    this.highlightSelected()
  }

  syncFromText() {
    const color = this.textInputTarget.value
    if (this.hasColorInputTarget) {
      this.colorInputTarget.value = color
    }
    this.updatePreview()
  }

  updatePreview() {
    const color = this.textInputTarget.value
    if (this.hasPreviewTarget) {
      this.previewTarget.style.setProperty("--ws-primary", color)
    }
  }

  highlightSelected() {
    const selected = this.textInputTarget.value.toLowerCase()
    this.swatchTargets.forEach(swatch => {
      const isSelected = swatch.dataset.color.toLowerCase() === selected
      swatch.classList.toggle("ring-2", isSelected)
      swatch.classList.toggle("ring-offset-2", isSelected)
      swatch.classList.toggle("ring-interactive-focus", isSelected)
      swatch.classList.toggle("scale-110", isSelected)
      swatch.setAttribute("aria-checked", isSelected)
    })
  }
}
