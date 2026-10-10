import { Controller } from "@hotwired/stimulus"

// Opens and closes the off-canvas sidebar on narrow screens.
export default class extends Controller {
  static targets = ["button"]

  toggle() {
    const open = this.element.classList.toggle("sidebar-open")
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
