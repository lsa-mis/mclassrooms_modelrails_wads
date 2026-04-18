import { Controller } from "@hotwired/stimulus"

// Declarative file picker trigger. When this controller connects (rendered
// by the server when Photo is selected with no image), it clicks the hidden
// file input to open the native OS file dialog.
//
// Sets the identity-picker controller's _filePickerOpen flag so that cancel
// events fired by the browser when the OS file dialog is dismissed don't
// propagate and close the modal.
export default class extends Controller {
  static values = { target: String }

  connect() {
    const input = document.querySelector(this.targetValue)
    if (!input) return

    // Notify the identity-picker controller that a file picker is opening
    const pickerEl = document.querySelector("[data-controller~='identity-picker']")
    const pickerCtrl = pickerEl && this.application.getControllerForElementAndIdentifier(pickerEl, "identity-picker")
    if (pickerCtrl) pickerCtrl._filePickerOpen = true

    setTimeout(() => input.click(), 0)
  }
}
