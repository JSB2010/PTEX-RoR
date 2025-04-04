import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "statsRefresh"]
  static values = {
    refreshInterval: { type: Number, default: 30000 } // 30 seconds
  }

  connect() {
    // Enable form validation
    if (this.hasFormTarget) {
      this.validateForm()
    }

    // Start stats auto-refresh if on system page
    if (this.hasStatsRefreshTarget) {
      this.startStatsRefresh()
    }
  }

  disconnect() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  validateForm(event) {
    if (!this.formTarget.checkValidity()) {
      event.preventDefault()
      event.stopPropagation()
    }
    this.formTarget.classList.add('was-validated')
  }

  clearCache(event) {
    if (confirm('Are you sure you want to clear the entire cache?')) {
      fetch('/admin/clear_cache', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      }).then(response => {
        if (response.ok) {
          window.location.reload()
        }
      })
    }
  }

  downloadLogs() {
    window.location.href = '/admin/download_logs'
  }

  startStatsRefresh() {
    this.refreshStats()
    this.refreshTimer = setInterval(() => {
      this.refreshStats()
    }, this.refreshIntervalValue)
  }

  async refreshStats() {
    const response = await fetch('/admin/system')
    if (response.ok) {
      const html = await response.text()
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, 'text/html')
      
      // Update only the dynamic parts
      const statsElements = doc.querySelectorAll('[data-refresh="true"]')
      statsElements.forEach(newElement => {
        const currentElement = document.querySelector(`#${newElement.id}`)
        if (currentElement) {
          currentElement.innerHTML = newElement.innerHTML
        }
      })
    }
  }
}