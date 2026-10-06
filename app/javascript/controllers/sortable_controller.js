import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag rows (by .drag-handle) to reorder. PATCHes the moved row's data-sortable-url
// with its new 1-based position and reports progress in data-sortable-state.
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
    const response = await fetch(item.dataset.sortableUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ position: newIndex + 1 })
    })
    this.element.dataset.sortableState = response.ok ? "saved" : "error"
  }
}
