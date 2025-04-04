import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["table", "title"]

  connect() {
    this.setupListeners()
  }

  setupListeners() {
    this.element.addEventListener('show.bs.modal', (event) => {
      const button = event.relatedTarget
      const courseId = button.dataset.courseId
      const courseName = button.dataset.courseName
      
      this.titleTarget.textContent = `Students - ${courseName}`
      this.loadStudents(courseId)
    })
  }

  async loadStudents(courseId) {
    const tbody = this.tableTarget.querySelector('tbody')
    tbody.innerHTML = '<tr><td colspan="4" class="text-center"><div class="spinner-border spinner-border-sm me-2"></div>Loading students...</td></tr>'

    try {
      const response = await fetch(`/admin/courses/${courseId}/students`)
      const data = await response.json()

      if (data.students && data.students.length > 0) {
        tbody.innerHTML = data.students.map(student => this.renderStudentRow(student)).join('')
      } else {
        tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted py-4"><i class="bi bi-people h4 d-block mb-2"></i>No students enrolled</td></tr>'
      }
    } catch (error) {
      tbody.innerHTML = '<tr><td colspan="4" class="text-center text-danger"><i class="bi bi-exclamation-triangle me-2"></i>Error loading students</td></tr>'
    }
  }

  renderStudentRow(student) {
    return `
      <tr>
        <td>
          <div class="d-flex align-items-center">
            <div class="flex-shrink-0">
              <div class="bg-light rounded-circle p-2">
                <i class="bi bi-person"></i>
              </div>
            </div>
            <div class="flex-grow-1 ms-3">
              <div>${student.name}</div>
              <small class="text-muted">${student.email}</small>
            </div>
          </div>
        </td>
        <td>
          <span class="badge bg-${student.grade_class}">${student.grade || 'N/A'}</span>
        </td>
        <td>
          <small class="text-muted">${student.updated_at || 'Never'}</small>
        </td>
        <td>
          <div class="btn-group">
            <button class="btn btn-sm btn-outline-primary" title="Edit grade">
              <i class="bi bi-pencil-square"></i>
            </button>
            <button class="btn btn-sm btn-outline-danger" title="Remove student">
              <i class="bi bi-person-x"></i>
            </button>
          </div>
        </td>
      </tr>
    `
  }
}