import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    // Close dropdown when clicking outside
    document.addEventListener('click', this.handleClickOutside)
  }

  disconnect() {
    document.removeEventListener('click', this.handleClickOutside)
  }

  toggle(event) {
    event.stopPropagation()
    this.menuTarget.classList.toggle('show')
  }

  handleClickOutside = (event) => {
    if (!this.element.contains(event.target) && this.menuTarget.classList.contains('show')) {
      this.menuTarget.classList.remove('show')
    }
  }
}