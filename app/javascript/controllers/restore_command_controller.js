import { Controller } from "@hotwired/stimulus"

// Fills the chosen snapshot's date into the restore command on the Backups page.
export default class extends Controller {
  static targets = ["select", "date"]

  update() {
    this.dateTargets.forEach((el) => { el.textContent = this.selectTarget.value })
  }
}
