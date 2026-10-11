import { Turbo } from "@hotwired/turbo-rails"

// data-turbo-confirm opens the styled <dialog> from the layout instead of window.confirm.
// The confirm button repeats the submit button's label ("Delete", "Archive", ...).
Turbo.config.forms.confirm = (message, _form, submitter) => {
  const dialog = document.getElementById("confirm-dialog")
  if (!dialog) return Promise.resolve(window.confirm(message))

  dialog.querySelector("p").textContent = message
  dialog.querySelector("button[value=confirm]").textContent = submitter?.textContent.trim() || "Confirm"
  dialog.returnValue = ""
  dialog.showModal()
  return new Promise(resolve => {
    dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), { once: true })
  })
}
