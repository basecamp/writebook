import { Controller } from "@hotwired/stimulus"

// Client-side search for the Writebook static export. Replaces the server's
// POST /books/:id/search (SQLite FTS5 over leaf_search_index) with an in-memory
// search over a per-book _search.json index built at export time (see
// Writebook::StaticExporter#build_search_index).
//
// The exporter attaches this controller to the existing <form id="search_form">
// inside the search dialog and sets data-static-search-index-path to the
// relative path to the book's _search.json. The search input (#search, which
// lives outside the form and references it via form="search_form") and the
// <turbo-frame id="search"> that holds the form are queried by id, since they
// are not descendants of the controller element.
//
// Results render into a .search__results div appended after the form inside the
// <turbo-frame id="search">, mirroring the server's _results/_result markup
// (title with <mark>, ~20-token content snippet with <mark>, a reading-mode
// link carrying ?search= so the destination page highlights matches, "No
// matches." empty state, 50-result cap, title hits weighted 2x like the
// server's bm25(leaf_search_index, 2.0)).
//
// This controller is eager-loaded in the live app too (via the importmap's
// pin_all_from "app/javascript/controllers"), but it only activates where
// data-controller="static-search" is present, which the exporter injects only
// into exported pages -- so the live app's server-side search is untouched.
export default class extends Controller {
  connect() {
    this.entries = null       // Array of { id, slug, title, url, content }
    this.titleIndex = null    // Map<term, Set<entryIndex>>
    this.contentIndex = null  // Map<term, Set<entryIndex>>
    this._loading = null
    this._timer = null
    this.element.addEventListener("submit", this.handleSubmit)
    const input = this.input
    if (input) input.addEventListener("input", this.handleInput)
  }

  disconnect() {
    this.element.removeEventListener("submit", this.handleSubmit)
    const input = this.input
    if (input) input.removeEventListener("input", this.handleInput)
    clearTimeout(this._timer)
  }

  get input()  { return document.getElementById("search") }
  get frame() { return document.querySelector('turbo-frame[id="search"]') }
  get indexPath() { return this.element.dataset.staticSearchIndexPath }

  // Fetch and build the index on first interaction. Resolves to the entries
  // array, or null if the index could not be loaded. Concurrent callers share
  // one in-flight promise. The URL is the controller's relative index path
  // resolved against location.pathname with a trailing slash, mirroring the
  // sidebar fetch so it works at a domain root and under any subpath.
  ensureIndex() {
    if (this.entries) return Promise.resolve(this.entries)
    if (this._loading) return this._loading
    let p = location.pathname
    if (!p.endsWith("/")) p += "/"
    this._loading = fetch(p + this.indexPath)
      .then((r) => r.ok ? r.json() : null)
      .then((data) => { if (data) { this.entries = data; this.buildIndex() } return data })
      .catch(() => null)
    return this._loading
  }

  buildIndex() {
    this.titleIndex = new Map()
    this.contentIndex = new Map()
    const add = (map, term, i) => {
      let set = map.get(term); if (!set) { set = new Set(); map.set(term, set) }
      set.add(i)
    }
    this.entries.forEach((entry, i) => {
      this.tokenize(entry.title).forEach((t) => add(this.titleIndex, t, i))
      this.tokenize(entry.content).forEach((t) => add(this.contentIndex, t, i))
    })
  }

  tokenize(text) { return (text || "").toLowerCase().split(/[^0-9a-z]+/).filter(Boolean) }
  queryTerms(q)  { return (q || "").toLowerCase().split(/[^0-9a-z]+/).filter(Boolean) }

  handleSubmit = (event) => { event.preventDefault(); this.run(this.input ? this.input.value : "") }

  handleInput = (event) => {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.run(event.target.value), 120)
  }

  async run(query) {
    const data = await this.ensureIndex()
    if (!data) { this.render([]); return }
    const terms = this.queryTerms(query)
    if (!terms.length) { this.render([]); return }
    const scores = new Map()
    terms.forEach((term) => {
      ;(this.titleIndex.get(term) || []).forEach((i) => scores.set(i, (scores.get(i) || 0) + 2))
      ;(this.contentIndex.get(term) || []).forEach((i) => scores.set(i, (scores.get(i) || 0) + 1))
    })
    const hits = []
    scores.forEach((score, i) => hits.push({ entry: data[i], score }))
    hits.sort((a, b) => b.score - a.score)
    this.render(hits.slice(0, 50), terms)
  }

  render(hits, terms) {
    const frame = this.frame
    if (!frame) return
    let results = frame.querySelector(":scope > .search__results")
    if (!results) {
      results = document.createElement("div")
      results.className = "search__results flex flex-column margin-block-start"
      frame.appendChild(results)
    }
    if (!hits || !hits.length) {
      results.innerHTML = '<p class="search__no_matches txt-align-center">No matches.</p>'
      return
    }
    const q = (this.input && this.input.value) || ""
    results.innerHTML = hits.map(({ entry }) => {
      const href = entry.url + "?search=" + encodeURIComponent(q)
      const title = this.highlight(entry.title, terms)
      const snippet = this.snippet(entry.content, terms)
      return `<a class="search__result hide_from_edit_mode txt-ink" data-turbo-frame="_top" href="${this.escapeAttr(href)}"><strong>${title}:</strong> ${snippet}</a>`
    }).join("")
  }

  // Wrap whole-word matches of any term in <mark>. The text is HTML-escaped first,
  // so only the literal <mark> tags we insert become live markup. Longest terms
  // first so a longer term wins before a shorter one nested inside it. Mirrors
  // SearchesHelper#whole_word_matchers (/\bterm\b/).
  highlight(text, terms) {
    const escaped = this.escapeHtml(text || "")
    const sorted = [...(terms || [])].sort((a, b) => b.length - a.length)
    let out = escaped
    sorted.forEach((term) => {
      const e = this.escapeHtml(term).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
      out = out.replace(new RegExp("\\b" + e + "\\b", "gi"), (m) => "<mark>" + m + "</mark>")
    })
    return out
  }

  // A ~20-token window (10 words either side of the first whole-word match),
  // elided with "..." when truncated, matches wrapped in <mark> -- mirroring
  // FTS5 snippet(…, '...', 20). Title-only hits fall back to a leading window.
  snippet(content, terms) {
    const text = (content || "").replace(/\s+/g, " ").trim()
    if (!text) return ""
    const low = text.toLowerCase()
    const sorted = [...(terms || [])].sort((a, b) => b.length - a.length)
    let at = -1, term = ""
    for (const t of sorted) {
      const m = new RegExp("\\b" + t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\b").exec(low)
      if (m) { at = m.index; term = t; break }
    }
    if (at === -1) {
      const head = text.split(" ").slice(0, 20).join(" ")
      return this.escapeHtml(head) + (text.length > head.length ? " ..." : "")
    }
    const before = text.slice(0, at)
    const match = text.slice(at, at + term.length)
    const after = text.slice(at + term.length)
    const W = 10
    const bWords = before.split(" ").filter(Boolean)
    const aWords = after.split(" ").filter(Boolean)
    const keepB = bWords.slice(Math.max(0, bWords.length - W))
    const keepA = aWords.slice(0, W)
    const lead = bWords.length > W ? "... " : ""
    const trail = aWords.length > W ? " ..." : ""
    const parts = []
    if (keepB.length) parts.push(this.highlight(keepB.join(" "), sorted))
    parts.push("<mark>" + this.escapeHtml(match) + "</mark>")
    if (keepA.length) parts.push(this.highlight(keepA.join(" "), sorted))
    return lead + parts.join(" ") + trail
  }

  escapeHtml(s) {
    return (s || "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
  }

  escapeAttr(s) { return (s || "").replace(/"/g, "&quot;") }
}