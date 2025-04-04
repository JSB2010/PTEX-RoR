// Configure your import map in config/importmap.rb
import "@hotwired/turbo-rails"
import "controllers"
import * as bootstrap from "bootstrap"

// Initialize Bootstrap components
document.addEventListener("turbo:load", () => {
  // Initialize all tooltips
  const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
  tooltipTriggerList.forEach(tooltipTriggerEl => {
    new bootstrap.Tooltip(tooltipTriggerEl, {
      container: 'body'
    })
  })

  // Initialize all popovers
  const popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'))
  popoverTriggerList.forEach(popoverTriggerEl => {
    new bootstrap.Popover(popoverTriggerEl)
  })

  // Initialize any existing toasts
  const toastElList = [].slice.call(document.querySelectorAll('.toast'))
  toastElList.map(function (toastEl) {
    return new bootstrap.Toast(toastEl, { delay: 3000 })
  })
})

// Create and show a toast message
function showToast(message, type = 'success') {
  const flashContainer = document.getElementById("flash-messages")
  if (flashContainer) {
    const alert = document.createElement("div")
    alert.className = `alert alert-${type} alert-dismissible fade show animate-slide-in`
    alert.setAttribute("role", "alert")
    
    const icon = type === 'success' ? 'check-circle' : 
                 type === 'danger' ? 'exclamation-circle' :
                 type === 'warning' ? 'exclamation-triangle' : 'info-circle'
    
    alert.innerHTML = `
      <div class="d-flex align-items-center">
        <i class="bi bi-${icon} fs-4 me-2"></i>
        <div>${message}</div>
      </div>
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `
    flashContainer.appendChild(alert)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      alert.classList.remove('show')
      setTimeout(() => alert.remove(), 150)
    }, 5000)
  }
}

// Handle AJAX form submission success
document.addEventListener("turbo:submit-end", (event) => {
  if (event.detail.success) {
    showToast("Changes saved successfully!")
  }
})

// Handle AJAX errors
document.addEventListener("turbo:fetch-request-error", (event) => {
  const statusCode = event.detail.fetchResponse?.response?.status
  let errorMessage = "An error occurred. Please try again."
  
  if (statusCode === 422) {
    errorMessage = "Please check your input and try again."
  } else if (statusCode === 404) {
    errorMessage = "The requested resource was not found."
  } else if (statusCode === 403) {
    errorMessage = "You don't have permission to perform this action."
  } else if (statusCode === 401) {
    errorMessage = "Your session has expired. Please sign in again."
    window.location.href = '/users/sign_in'
  } else if (statusCode === 413) {
    errorMessage = "The file you're trying to upload is too large."
  } else if (statusCode >= 500) {
    errorMessage = "A server error occurred. Our team has been notified."
  }
  
  showToast(errorMessage, 'danger')
})

// Handle file upload errors
document.addEventListener("direct-upload:error", (event) => {
  const { error } = event.detail
  showToast(`File upload failed: ${error}`, 'danger')
})

// Handle network errors
window.addEventListener("offline", () => {
  showToast("You appear to be offline. Some features may be unavailable.", 'warning')
})

// Handle server validation errors with field-specific feedback
document.addEventListener("turbo:submit-end", (event) => {
  if (!event.detail.success) {
    const formElement = event.target
    const errorElements = formElement.querySelectorAll('.is-invalid')
    if (errorElements.length > 0) {
      showToast("Please correct the errors and try again.", 'warning')
      // Focus the first invalid field
      const firstInvalid = formElement.querySelector('.is-invalid')
      firstInvalid?.focus()
    }
  }
})

// Handle form submission success with custom messages
document.addEventListener("turbo:submit-end", (event) => {
  if (event.detail.success) {
    const formElement = event.target
    const successMessage = formElement.dataset.successMessage || "Changes saved successfully!"
    showToast(successMessage, 'success')
  }
})

// Ensure Devise logout redirects are properly handled
document.addEventListener("turbo:before-visit", (event) => {
  if (event.detail.url.includes('/users/sign_out')) {
    // Force a full page reload for sign out to ensure proper session clearing
    event.preventDefault()
    window.location.href = event.detail.url
  }
})