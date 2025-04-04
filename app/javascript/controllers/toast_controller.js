import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]
  static values = {
    autohide: { type: Boolean, default: true },
    delay: { type: Number, default: 3000 }
  }

  connect() {
    this.toasts = new Map()
  }

  show({ detail: { message, type = "success" } }) {
    const toast = this.createToast(message, type)
    this.containerTarget.appendChild(toast)
    
    const bsToast = new bootstrap.Toast(toast, {
      autohide: this.autohideValue,
      delay: this.delayValue
    })
    
    this.toasts.set(toast, bsToast)
    bsToast.show()

    toast.addEventListener('hidden.bs.toast', () => {
      this.toasts.delete(toast)
      toast.remove()
    })
  }

  createToast(message, type) {
    const toast = document.createElement('div')
    toast.className = `toast align-items-center text-white bg-${type} border-0`
    toast.setAttribute('role', 'alert')
    toast.setAttribute('aria-live', 'assertive')
    toast.setAttribute('aria-atomic', 'true')
    
    toast.innerHTML = `
      <div class="d-flex">
        <div class="toast-body">
          ${message}
        </div>
        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
      </div>
    `
    
    return toast
  }

  disconnect() {
    this.toasts.forEach(toast => toast.dispose())
    this.toasts.clear()
  }
}