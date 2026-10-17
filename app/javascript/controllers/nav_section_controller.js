import { Controller } from "@hotwired/stimulus"

// Remembers whether the sidebar's Settings section is open, so the server renders it the same way on the next page.
export default class extends Controller {
  remember() {
    // Runs before the <details> toggles, so the new state is the opposite of the current one.
    const state = this.element.open ? "closed" : "open"
    document.cookie = `settings_nav=${state}; path=/; max-age=31536000; SameSite=Lax`
  }
}
