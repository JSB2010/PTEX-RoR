import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["numericGrade", "letterGrade", "statistics"]
  static values = {
    courseId: String,
    updateUrl: String
  }

  connect() {
    if (this.hasStatisticsTarget) {
      this.refreshInterval = setInterval(() => {
        this.refreshStatistics()
      }, 30000) // Refresh every 30 seconds
    }
  }

  disconnect() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
    }
  }

  async updateGrade(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)

    try {
      const response = await fetch(this.updateUrlValue, {
        method: 'PATCH',
        body: formData,
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        this.refreshStatistics()
        const data = await response.json()
        this.letterGradeTarget.textContent = data.letter_grade
        this.letterGradeTarget.className = `letter-grade badge ${this.getGradeBadgeClass(data.letter_grade)}`
      } else {
        const error = await response.json()
        this.showError(error.message || 'Failed to update grade')
      }
    } catch (error) {
      console.error('Error updating grade:', error)
      this.showError('Network error occurred')
    }
  }

  async refreshStatistics() {
    if (!this.hasStatisticsTarget) return

    try {
      const response = await fetch(`/courses/${this.courseIdValue}/stats`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        const html = await response.text()
        this.statisticsTarget.innerHTML = html
      }
    } catch (error) {
      console.error('Error refreshing statistics:', error)
    }
  }

  getGradeBadgeClass(grade) {
    switch(true) {
      case /^A/.test(grade):
        return 'bg-success'
      case /^B/.test(grade):
        return 'bg-primary'
      case /^C/.test(grade):
        return 'bg-warning'
      case /^D/.test(grade):
        return 'bg-danger'
      default:
        return 'bg-secondary'
    }
  }

  showError(message) {
    const toast = document.createElement('div')
    toast.className = 'toast align-items-center text-white bg-danger border-0'
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
    
    document.body.appendChild(toast)
    const bsToast = new bootstrap.Toast(toast)
    bsToast.show()
    
    toast.addEventListener('hidden.bs.toast', () => {
      toast.remove()
    })
  }
}