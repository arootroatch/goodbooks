import { Controller } from "@hotwired/stimulus"

// Shows or hides a tithe week's transaction rows under its summary row.
export default class extends Controller {
  static targets = ["toggle", "entry"]

  toggle() {
    const open = this.toggleTarget.getAttribute("aria-expanded") !== "true"
    this.toggleTarget.setAttribute("aria-expanded", open)
    this.entryTargets.forEach((row) => { row.hidden = !open })
  }
}
