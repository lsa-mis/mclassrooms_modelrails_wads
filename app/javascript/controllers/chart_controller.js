// Chart.js is an OPT-IN dependency — pin it only when you use the chart component:
//   bin/importmap pin chart.js   (downloads to vendor/javascript — production CSP allows no CDN)
// It is imported lazily (inside connect), so this controller is inert until a chart
// is on the page: an app that adopts the component but never renders one pays nothing,
// and an app that hasn't pinned Chart.js gets a one-line hint, not a per-page error.
// The accessible data table renders server-side regardless.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    type: { type: String, default: "bar" },
    config: { type: String, default: "{}" }
  }

  #chart = null

  async connect() {
    let Chart, registerables
    try {
      ({ Chart, registerables } = await import("chart.js"))
    } catch {
      console.info(
        '[ui:chart] Chart.js is not pinned — the chart will not draw. Add to config/importmap.rb:\n' +
        '  bin/importmap pin chart.js   # downloads to vendor/javascript; production CSP allows no CDN\n' +
        "The accessible data table renders without it."
      )
      return
    }
    Chart.register(...registerables)

    const { labels, datasets, options = {} } = JSON.parse(this.configValue)
    this.#chart = new Chart(this.element, {
      type: this.typeValue,
      data: { labels, datasets },
      options: { responsive: true, maintainAspectRatio: true, ...options }
    })
  }

  disconnect() {
    this.#chart?.destroy()
    this.#chart = null
  }
}
