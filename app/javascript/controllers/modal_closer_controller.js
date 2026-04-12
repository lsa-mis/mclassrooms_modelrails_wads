import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Find the nearest open dialog and close it through the modal controller
    // to ensure proper focus restoration
    const dialog = this.element.closest("dialog")
    if (dialog?.open) {
      const modalController = this.application.getControllerForElementAndIdentifier(
        dialog.closest("[data-controller~='modal']"),
        "modal"
      )

      if (modalController) {
        modalController.close()
      } else {
        dialog.close()
      }
    }

    // Remove self after closing
    this.element.remove()
  }
}
