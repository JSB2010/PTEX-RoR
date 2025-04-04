import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["systemStatus", "cacheStats", "jobStats"]
  static values = {
    refreshInterval: { type: Number, default: 30000 }, // 30 seconds
    chartData: Object
  }

  connect() {
    if (this.hasSystemStatusTarget) {
      this.startAutoRefresh()
    }
  }

  disconnect() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  startAutoRefresh() {
    this.refreshSystemStatus()
    this.refreshTimer = setInterval(() => {
      this.refreshSystemStatus()
    }, this.refreshIntervalValue)
  }

  async refreshSystemStatus() {
    try {
      const response = await fetch('/admin/system', {
        headers: {
          'Accept': 'application/json'
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        this.updateSystemStatus(data)
      }
    } catch (error) {
      console.error('Error refreshing system status:', error)
    }
  }

  updateSystemStatus(data) {
    // Update system status indicators
    if (this.hasSystemStatusTarget) {
      const allHealthy = data.db_status && data.redis_status && data.sidekiq_status
      
      this.systemStatusTarget.innerHTML = `
        <div class="alert alert-${allHealthy ? 'success' : 'danger'} mb-0">
          <div class="d-flex align-items-center">
            <i class="bi bi-${allHealthy ? 'check-circle' : 'exclamation-triangle'} fs-4 me-2"></i>
            <div>
              <strong>${allHealthy ? 'All Systems Operational' : 'System Issues Detected'}</strong>
              <div class="small">Last checked: ${new Date().toLocaleTimeString()}</div>
            </div>
          </div>
        </div>
      `
    }

    // Update cache statistics
    if (this.hasCacheStatsTarget && data.cache_stats) {
      this.updateCacheStats(data.cache_stats)
    }

    // Update job statistics
    if (this.hasJobStatsTarget && data.job_stats) {
      this.updateJobStats(data.job_stats)
    }
  }

  updateCacheStats(stats) {
    const rows = Object.entries(stats).map(([key, value]) => `
      <tr>
        <td>${this.humanizeKey(key)}</td>
        <td class="text-end">${this.formatValue(value)}</td>
      </tr>
    `).join('')

    this.cacheStatsTarget.innerHTML = rows
  }

  updateJobStats(stats) {
    const rows = Object.entries(stats).map(([queue, count]) => `
      <tr>
        <td>${this.humanizeKey(queue)}</td>
        <td class="text-end">
          <span class="badge bg-${count > 0 ? 'primary' : 'secondary'}">${count}</span>
        </td>
      </tr>
    `).join('')

    this.jobStatsTarget.innerHTML = rows
  }

  humanizeKey(key) {
    return key.split('_')
            .map(word => word.charAt(0).toUpperCase() + word.slice(1))
            .join(' ')
  }

  formatValue(value) {
    if (typeof value === 'number') {
      return value.toLocaleString()
    }
    if (typeof value === 'boolean') {
      return value ? 'Yes' : 'No'
    }
    return value
  }
}