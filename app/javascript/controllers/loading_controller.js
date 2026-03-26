import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "disable" ]

  start() {
    this.disableTargets.forEach(el => el.disabled = true)
  }
}
