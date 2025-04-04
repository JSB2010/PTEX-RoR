import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["firstName", "lastName", "username"]

  generate() {
    if (this.firstNameTarget.value && this.lastNameTarget.value) {
      const firstName = this.firstNameTarget.value.trim()
      const lastName = this.lastNameTarget.value.trim()
      const username = (firstName[0] + lastName).toLowerCase().replace(/[^a-z0-9]/g, '')
      this.usernameTarget.value = username
    }
  }
}