import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.validateForm()
  }

  validateForm() {
    this.element.addEventListener('submit', (event) => {
      if (!this.element.checkValidity()) {
        event.preventDefault()
        event.stopPropagation()
      }
      this.element.classList.add('was-validated')
    }, false)
  }
}