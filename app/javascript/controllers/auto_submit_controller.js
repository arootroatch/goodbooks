import { Controller } from "@hotwired/stimulus"

// Submits the form whenever a field changes; typing waits for a pause.
export default class extends Controller {
  submit() {
    clearTimeout(this.timeout)
    this.element.requestSubmit()
  }

  debouncedSubmit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), 300)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
