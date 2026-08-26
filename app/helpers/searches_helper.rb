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
    # Terms come from FTS5 highlight() spans, which can include document
    # punctuation (e.g. a phrase match spanning "alpha(beta"). Escape them so
    # metacharacters are matched literally instead of raising a RegexpError.
    def whole_word_matchers(terms)
      terms.map { |term| /\b#{Regexp.escape(term)}\b/ }
    end
end
