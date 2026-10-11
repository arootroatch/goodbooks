import { Controller } from "@hotwired/stimulus"

// Keeps a link's query string in step with a filter form elsewhere on the page (e.g. Download CSV in the header).
export default class extends Controller {
  static values = { form: String }

  connect() {
    this.form = document.getElementById(this.formValue)
    this.sync = this.sync.bind(this)
    this.form?.addEventListener("change", this.sync)
    this.form?.addEventListener("input", this.sync)
  }

  disconnect() {
    this.form?.removeEventListener("change", this.sync)
    this.form?.removeEventListener("input", this.sync)
  }

  sync() {
    const url = new URL(this.element.href)
    url.search = ""
    for (const [key, value] of new FormData(this.form)) {
      if (value !== "") url.searchParams.set(key, value)
    }
    this.element.href = url.toString()
  }
}
