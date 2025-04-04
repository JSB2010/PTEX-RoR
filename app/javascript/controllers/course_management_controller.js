import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["addStudentsForm", "studentSelect"]

  connect() {
    if (this.hasAddStudentsFormTarget) {
      this.initializeStudentSelect()
      this.setupModalHandlers()
    }
  }

  initializeStudentSelect() {
    // Initialize Select2 for better UX on student selection
    $(this.studentSelectTarget).select2({
      theme: 'bootstrap-5',
      width: '100%',
      placeholder: 'Select students to add...',
      allowClear: true
    })
  }

  setupModalHandlers() {
    const modal = document.getElementById('addStudentsModal')
    modal.addEventListener('show.bs.modal', event => {
      const button = event.relatedTarget
      const courseId = button.getAttribute('data-course-id')
      this.addStudentsFormTarget.action = `/courses/${courseId}/add_student`
    })

    modal.addEventListener('hidden.bs.modal', () => {
      $(this.studentSelectTarget).val(null).trigger('change')
    })
  }

  clearSelection() {
    $(this.studentSelectTarget).val(null).trigger('change')
  }

  async submitForm(event) {
    event.preventDefault()
    
    if (!this.addStudentsFormTarget.checkValidity()) {
      event.stopPropagation()
      this.addStudentsFormTarget.classList.add('was-validated')
      return
    }

    const formData = new FormData(this.addStudentsFormTarget)
    
    try {
      const response = await fetch(this.addStudentsFormTarget.action, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        window.location.reload()
      } else {
        throw new Error('Failed to add students')
      }
    } catch (error) {
      console.error('Error adding students:', error)
      // Show error message
      const toast = document.getElementById('errorToast')
      if (toast) {
        const toastInstance = new bootstrap.Toast(toast)
        toast.querySelector('.toast-body').textContent = 'Failed to add students to course'
        toastInstance.show()
      }
    }
  }
}