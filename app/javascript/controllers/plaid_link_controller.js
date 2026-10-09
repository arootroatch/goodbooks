import { Controller } from "@hotwired/stimulus"

const PLAID_SCRIPT = "https://cdn.plaid.com/link/v2/stable/link-initialize.js"

// Opens Plaid Link and posts the public token it returns. With the fake gateway it skips Plaid and posts a fake token.
export default class extends Controller {
  static targets = ["button", "form", "publicToken", "status"]
  static values = { token: String, fake: Boolean }

  async open() {
    this.buttonTarget.disabled = true
    if (this.fakeValue) return this.submit(`public-fake-${Date.now()}`)

    try {
      await this.loadScript()
      window.Plaid.create({
        token: this.tokenValue,
        onSuccess: (publicToken) => this.submit(publicToken),
        onExit: (error) => {
          this.buttonTarget.disabled = false
          if (error) this.statusTarget.textContent = error.display_message || error.error_message || "Plaid closed with an error."
        }
      }).open()
    } catch {
      this.buttonTarget.disabled = false
      this.statusTarget.textContent = "Couldn't load Plaid. Check your connection and try again."
    }
  }

  submit(publicToken) {
    this.publicTokenTarget.value = publicToken
    this.formTarget.requestSubmit()
  }

  loadScript() {
    if (window.Plaid) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = PLAID_SCRIPT
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  }
}
