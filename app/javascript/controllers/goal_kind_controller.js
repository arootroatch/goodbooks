import { Controller } from "@hotwired/stimulus"

// Shows the matcher fields for payment goals and the account select for savings goals.
export default class extends Controller {
  static targets = ["payments", "savings"]

  toggle(event) {
    const savings = event.target.value === "savings"
    this.paymentsTarget.hidden = savings
    this.savingsTarget.hidden = !savings
  }
}
