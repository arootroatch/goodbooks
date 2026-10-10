import { Controller } from "@hotwired/stimulus"

// Applies a theme instantly and stores it in the same cookie the server reads.
export default class extends Controller {
  static targets = ["option"]

  choose(event) {
    event.preventDefault()
    const theme = event.target.querySelector("input[name=theme]").value
    document.cookie = `theme=${theme}; path=/; max-age=31536000; samesite=lax`

    if (theme === "system") {
      delete document.documentElement.dataset.theme
    } else {
      document.documentElement.dataset.theme = theme
    }

    this.optionTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.themeChoice === theme))
    })
  }
}
