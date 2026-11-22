module SearchesHelper
  # Use this method to ensure FTS5 search result output is safe to render,
  # allowing only <mark> tags through.
  #
  # FTS5 highlight() and snippet() wrap matched terms in <mark> tags, but the
  # surrounding content may contain unsanitized HTML from user input,
  # particularly if it was indexed before explicit sanitization was added to
  # the Searchable concern.
  def sanitize_search_result(html)
    sanitize(html, tags: %w[mark], attributes: [])
  end

  # The same FTS5 output as plain text, for JSON clients: no markup at all,
  # entities decoded.
  def search_result_text(html)
    CGI.unescapeHTML strip_tags(html.to_s)
  end

  def highlight_searched_content(leaf, content, query)
    if query.present?
      terms = leaf.matches_for_highlight(query)
      terms = whole_word_matchers(terms)

      sanitize_content highlight(content, terms, sanitize: false)
    else
      content
    end
  end

  private
    def whole_word_matchers(terms)
      terms.map { |term| /\b#{Regexp.escape(term)}\b/ }
    end
end
