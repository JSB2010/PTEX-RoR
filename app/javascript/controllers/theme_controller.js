import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.initializeTheme()
  }
  
  initializeTheme() {
    const theme = localStorage.getItem('theme') || 'light'
    this.applyTheme(theme)
    
    // Update toggle state
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = theme === 'dark'
    }
  }
  
  toggle(event) {
    const theme = event.target.checked ? 'dark' : 'light'
    this.applyTheme(theme)
    localStorage.setItem('theme', theme)
  }
  
  applyTheme(theme) {
    if (theme === 'dark') {
      document.documentElement.classList.add('dark-theme')
    } else {
      document.documentElement.classList.remove('dark-theme')
    }
  }
}