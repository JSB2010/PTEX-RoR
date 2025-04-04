import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "text"]

  connect() {
    document.addEventListener('turbo:request-start', this.showLoading)
    document.addEventListener('turbo:request-end', this.hideLoading)
  }

  disconnect() {
    document.removeEventListener('turbo:request-start', this.showLoading)
    document.removeEventListener('turbo:request-end', this.hideLoading)
  }

  showLoading = () => {
    this.overlayTarget.classList.add('active')
  }

  hideLoading = () => {
    this.overlayTarget.classList.remove('active')
  }

  setText(text) {
    if (this.hasTextTarget) {
      this.textTarget.textContent = text
    }
  }
}