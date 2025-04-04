import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "cacheHitRate", 
    "cacheHits", 
    "cacheMisses", 
    "calculationStats",
    "errorStats",
    "coursePerformance"
  ]

  connect() {
    this.startPolling()
  }

  disconnect() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
    }
  }

  startPolling() {
    // Poll every 30 seconds
    this.pollingInterval = setInterval(() => {
      this.refreshMetrics()
    }, 30000)
  }

  async refreshMetrics() {
    try {
      const response = await fetch('/performance_metrics.json')
      const data = await response.json()
      
      this.updateCache(data.metrics.cache_hits)
      this.updateCalculations(data.metrics.calculation_times)
      this.updateErrors(data.metrics.error_rates)
      this.updateCoursePerformance(data.statistics)
    } catch (error) {
      console.error('Error refreshing metrics:', error)
    }
  }

  updateCache(cacheData) {
    if (this.hasCacheHitRateTarget) {
      const rate = cacheData.rate
      this.cacheHitRateTarget.style.width = `${rate}%`
      this.cacheHitRateTarget.textContent = `${rate}% Cache Hit Rate`
      
      // Update color based on performance
      const classes = ['bg-danger', 'bg-warning', 'bg-info', 'bg-success']
      classes.forEach(cls => this.cacheHitRateTarget.classList.remove(cls))
      
      if (rate <= 30) this.cacheHitRateTarget.classList.add('bg-danger')
      else if (rate <= 60) this.cacheHitRateTarget.classList.add('bg-warning')
      else if (rate <= 80) this.cacheHitRateTarget.classList.add('bg-info')
      else this.cacheHitRateTarget.classList.add('bg-success')
    }

    if (this.hasCacheHitsTarget) {
      this.cacheHitsTarget.textContent = cacheData.hits
    }

    if (this.hasCacheMissesTarget) {
      this.cacheMissesTarget.textContent = cacheData.misses
    }
  }

  updateCalculations(calculationData) {
    if (this.hasCalculationStatsTarget) {
      const tbody = this.calculationStatsTarget.querySelector('tbody')
      tbody.innerHTML = Object.entries(this.groupByType(calculationData))
        .map(([type, measurements]) => {
          const avgTime = measurements.reduce((sum, m) => sum + m.time, 0) / measurements.length
          return `
            <tr>
              <td>${this.humanize(type)}</td>
              <td>${this.formatTime(avgTime)}</td>
            </tr>
          `
        })
        .join('')
    }
  }

  updateErrors(errorData) {
    if (this.hasErrorStatsTarget) {
      const tbody = this.errorStatsTarget.querySelector('tbody')
      if (Object.keys(errorData).length === 0) {
        this.errorStatsTarget.innerHTML = '<p class="text-muted">No errors recorded in the last hour.</p>'
      } else {
        tbody.innerHTML = Object.entries(errorData)
          .map(([type, count]) => `
            <tr>
              <td>${this.humanize(type)}</td>
              <td>${count}</td>
            </tr>
          `)
          .join('')
      }
    }
  }

  updateCoursePerformance(courseData) {
    if (this.hasCoursePerformanceTarget) {
      const tbody = this.coursePerformanceTarget.querySelector('tbody')
      tbody.innerHTML = courseData
        .map(stats => {
          const status = this.determineStatus(stats)
          return `
            <tr>
              <td>${stats.name}</td>
              <td>
                ${this.formatTime(stats.calculation_time)}
                ${stats.calculation_time > 1000 ? '<span class="badge bg-warning">Slow</span>' : ''}
              </td>
              <td>
                ${stats.cache_hit_rate}%
                ${stats.cache_hit_rate < 50 ? '<span class="badge bg-danger">Low Cache Hits</span>' : ''}
              </td>
              <td>
                <span class="badge bg-${status.color}">${status.label}</span>
              </td>
            </tr>
          `
        })
        .join('')
    }
  }

  // Helper methods
  groupByType(measurements) {
    return measurements.reduce((groups, item) => {
      const group = (groups[item.calculation_type] || [])
      group.push(item)
      groups[item.calculation_type] = group
      return groups
    }, {})
  }

  humanize(str) {
    return str
      .replace(/_/g, ' ')
      .replace(/\w\S*/g, txt => txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase())
  }

  formatTime(time) {
    return `${time.toFixed(2)}ms`
  }

  determineStatus(stats) {
    if (stats.calculation_time > 1000 && stats.cache_hit_rate < 50) {
      return { label: 'Critical', color: 'danger' }
    } else if (stats.calculation_time > 1000 || stats.cache_hit_rate < 50) {
      return { label: 'Warning', color: 'warning' }
    } else if (stats.calculation_time > 500) {
      return { label: 'Fair', color: 'info' }
    } else {
      return { label: 'Good', color: 'success' }
    }
  }
}