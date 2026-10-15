import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { Turbo } from "@hotwired/turbo-rails"

// Drag rows (by .drag-handle) to reorder. PATCHes the moved row's data-sortable-url
// with its new 1-based position and reports progress in data-sortable-state.
// A Turbo Stream response (e.g. redrawn goal bars) is rendered.
export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: ".drag-handle",
      forceFallback: true,
      onEnd: (event) => this.save(event)
    })
  }

  disconnect() {
    this.sortable.destroy()
  }

  async save({ item, newIndex, oldIndex }) {
    if (newIndex === oldIndex) return

    this.element.dataset.sortableState = "saving"
    this.sortable.option("disabled", true)
    try {
      const response = await fetch(item.dataset.sortableUrl, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ position: newIndex + 1 })
      })
      if (!response.ok) throw new Error(`Move failed: ${response.status}`)
      if (response.headers.get("Content-Type")?.startsWith("text/vnd.turbo-stream.html")) {
        Turbo.renderStreamMessage(await response.text())
      }
      this.element.dataset.sortableState = "saved"
    } catch {
      this.revert(item, oldIndex)
      this.element.dataset.sortableState = "error"
    } finally {
      this.sortable.option("disabled", false)
    }
  }

  revert(item, oldIndex) {
    item.remove()
    this.element.insertBefore(item, this.element.children[oldIndex] || null)
  }
}
