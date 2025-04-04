import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "calculationMetrics",
    "cacheMetrics",
    "errorOverview"
  ]

  connect() {
    this.refreshInterval = setInterval(() => {
      this.refreshMetrics(this.currentTimeRange)
    }, 60000) // Update every minute
    
    window.refreshMetrics = this.refreshMetrics.bind(this)
  }

  disconnect() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
    }
  }

  get currentTimeRange() {
    return document.querySelector('[data-time-range].active')?.dataset.timeRange || 'day'
  }

  async refreshMetrics(timeRange = 'day') {
    try {
      const response = await fetch(`/performance_metrics?time_range=${timeRange}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.updateDashboard(data)
      }
    } catch (error) {
      console.error('Error refreshing metrics:', error)
    }
  }

  updateDashboard(data) {
    if (this.hasCalculationMetricsTarget) {
      this.updateCalculationMetrics(data.course_statistics)
    }

    if (this.hasCacheMetricsTarget) {
      this.updateCacheMetrics(data.cache_metrics)
    }

    if (this.hasErrorOverviewTarget) {
      this.updateErrorOverview(data.error_rates)
    }
  }

  updateCalculationMetrics(stats) {
    this.calculationMetricsTarget.innerHTML = stats.map(stat => `
      <div class="metric-row mb-3">
        <div class="d-flex justify-content-between align-items-center mb-2">
          <span class="course-name">${stat.name}</span>
          <span class="calculation-time">
            ${Number(stat.calculation_time).toFixed(2)} ms
            ${stat.calculation_time > 1000 ? '<span class="badge bg-warning">Slow</span>' : ''}
          </span>
        </div>
        <div class="progress" style="height: 4px;">
          <div class="progress-bar ${this.cachePerformanceClass(stat.cache_hit_rate)}"
               role="progressbar"
               style="width: ${stat.cache_hit_rate}%"
               aria-valuenow="${stat.cache_hit_rate}"
               aria-valuemin="0"
               aria-valuemax="100">
          </div>
        </div>
        <small class="text-muted">
          Cache Hit Rate: ${stat.cache_hit_rate.toFixed(1)}%
        </small>
      </div>
    `).join('')
  }

  updateCacheMetrics(metrics) {
    const hitRateStatus = this.cacheHitRateStatus(metrics.rate)
    
    this.cacheMetricsTarget.innerHTML = `
      <div class="metric-group mb-4">
        <h6 class="text-muted">Overall Hit Rate</h6>
        <div class="d-flex align-items-center">
          <h2 class="mb-0 me-2">${metrics.rate.toFixed(1)}%</h2>
          <div class="metric-trend">
            <span class="badge ${hitRateStatus.class}">${hitRateStatus.label}</span>
          </div>
        </div>
      </div>

      <div class="row text-center">
        <div class="col">
          <div class="metric-box p-3 rounded bg-light">
            <small class="text-muted d-block">Cache Hits</small>
            <span class="h4 mb-0">${this.formatNumber(metrics.hits)}</span>
          </div>
        </div>
        <div class="col">
          <div class="metric-box p-3 rounded bg-light">
            <small class="text-muted d-block">Cache Misses</small>
            <span class="h4 mb-0">${this.formatNumber(metrics.misses)}</span>
          </div>
        </div>
      </div>
    `
  }

  updateErrorOverview(errors) {
    if (Object.keys(errors).length === 0) {
      this.errorOverviewTarget.innerHTML = `
        <p class="text-success mb-0">
          <i class="bi bi-check-circle me-2"></i>
          No errors reported
        </p>
      `
      return
    }

    this.errorOverviewTarget.innerHTML = `
      <div class="list-group list-group-flush">
        ${Object.entries(errors).map(([type, count]) => `
          <div class="list-group-item d-flex justify-content-between align-items-center">
            <span>${this.formatErrorType(type)}</span>
            <span class="badge bg-danger rounded-pill">${count}</span>
          </div>
        `).join('')}
      </div>
    `
  }

  cachePerformanceClass(rate) {
    if (rate >= 80) return 'bg-success'
    if (rate >= 60) return 'bg-info'
    if (rate >= 40) return 'bg-warning'
    return 'bg-danger'
  }

  cacheHitRateStatus(rate) {
    if (rate >= 80) return { class: 'bg-success', label: 'Excellent' }
    if (rate >= 60) return { class: 'bg-info', label: 'Good' }
    if (rate >= 40) return { class: 'bg-warning', label: 'Fair' }
    return { class: 'bg-danger', label: 'Poor' }
  }

  formatErrorType(type) {
    return type
      .split('_')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  }

  formatNumber(num) {
    return new Intl.NumberFormat().format(num)
  }
}