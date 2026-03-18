import { Controller } from "@hotwired/stimulus"
import { readCookie, setCookie } from "helpers/cookie_helpers"

export default class extends Controller {
  static targets = [ "switch" ]
  static values = { id: String, default: String }

  connect() {
    this.#restoreViewPref(this.idValue)
  }

  saveViewPref(event) {
    const viewType = event.target.dataset.tocViewTypeValue
    setCookie(this.idValue, viewType)
  }

  #restoreViewPref(id) {
    const viewType = readCookie(id) || this.defaultValue
    this.switchTargets.forEach(switchTarget => {
      switchTarget.checked = switchTarget.dataset.tocViewTypeValue === viewType
    })
  }
}
