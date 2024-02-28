import { Controller } from "@hotwired/stimulus"
import { createEditor } from "markdown-editor"

export default class extends Controller {
  connect() {
    this.editor = createEditor(this.element)
  }

  disconnect() {
    this.editor = null
  }
}
