import { Controller } from "@hotwired/stimulus"

// Opens and closes the off-canvas sidebar on narrow screens.
export default class extends Controller {
  static targets = ["button"]

  toggle() {
    this.#setOpen(!this.element.classList.contains("sidebar-open"))
  }

  close() {
    this.#setOpen(false)
  }

  #setOpen(open) {
    this.element.classList.toggle("sidebar-open", open)
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
