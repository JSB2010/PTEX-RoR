import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["numeric", "letter"]

  connect() {
    if (this.numericTarget.value) {
      this.updateLetterGrade()
    }
  }

  updateLetterGrade() {
    const score = parseFloat(this.numericTarget.value)
    if (isNaN(score)) return

    let letterGrade
    if (score > 100) letterGrade = 'A++'
    else if (score >= 97 && score <= 100) letterGrade = 'A+'
    else if (score >= 93 && score < 97) letterGrade = 'A'
    else if (score >= 90 && score < 93) letterGrade = 'A-'
    else if (score >= 87 && score < 90) letterGrade = 'B+'
    else if (score >= 83 && score < 87) letterGrade = 'B'
    else if (score >= 80 && score < 83) letterGrade = 'B-'
    else if (score >= 77 && score < 80) letterGrade = 'C+'
    else if (score >= 73 && score < 77) letterGrade = 'C'
    else if (score >= 70 && score < 73) letterGrade = 'C-'
    else if (score >= 67 && score < 70) letterGrade = 'D+'
    else if (score >= 60 && score < 67) letterGrade = 'D'
    else letterGrade = 'F'

    const formData = new FormData()
    formData.append('grade[numeric_grade]', score.toFixed(2))
    formData.append('grade[letter_grade]', letterGrade)

    fetch(this.element.action, {
      method: 'PATCH',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    }).then(response => {
      if (response.ok) {
        const letterDisplay = this.element.closest('tr').querySelector('.letter-grade')
        if (letterDisplay) {
          letterDisplay.textContent = `${letterGrade} (${score.toFixed(1)}%)`
        }
      }
    }).catch(error => {
      console.error('Error updating grade:', error)
    })
  }
}