// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "actions"
import "controllers"
import "house"
import mermaid from "mermaid"

const MERMAID_KEYWORDS = /^(flowchart|graph\s+(TD|TB|BT|RL|LR)|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt|pie|gitGraph|mindmap|timeline|sankey|xychart)\b/

document.addEventListener("turbo:load", () => {
  const theme = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default"
  mermaid.initialize({ startOnLoad: false, theme })

  const targets = [...document.querySelectorAll("pre > code.language-mermaid, pre.highlight.plaintext > code")]
    .filter(el => el.classList.contains("language-mermaid") || MERMAID_KEYWORDS.test(el.textContent.trim()))
  if (!targets.length) return

  targets.forEach(el => {
    const pre = el.closest("pre")
    if (!pre) return
    const div = document.createElement("div")
    div.className = "mermaid"
    div.textContent = el.textContent
    pre.replaceWith(div)
  })
  mermaid.run()
})

