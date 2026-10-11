import { Controller } from "@hotwired/stimulus"

// Shows a bar's data-tip right away on hover; the native SVG <title> waits about a second.
export default class extends Controller {
  connect() {
    this.tip = document.createElement("div")
    this.tip.className = "chart-tooltip"
    this.tip.hidden = true
    document.body.append(this.tip)
  }

  disconnect() {
    this.tip.remove()
  }

  show(event) {
    const bar = event.target.closest("[data-tip]")
    if (!bar) return

    const box = bar.getBoundingClientRect()
    this.tip.textContent = bar.dataset.tip
    this.tip.hidden = false
    this.tip.style.left = `${box.left + box.width / 2}px`
    this.tip.style.top = `${box.top}px`
  }

  hide(event) {
    if (event.target.closest("[data-tip]")) this.tip.hidden = true
  }
}
