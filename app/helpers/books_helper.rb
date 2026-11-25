module BooksHelper
  def can_edit?(book)
    signed_in? && !read_only_token? && Current.user.editor_of?(book)
  end

  def book_toc_tag(book, &)
    tag.ol class: "toc", tabindex: 0,
      data: {
        controller: "arrangement",
        action: arrangement_actions,
        arrangement_cursor_class: "arrangement-cursor",
        arrangement_selected_class: "arrangement-selected",
        arrangement_placeholder_class: "arrangement-placeholder",
        arrangement_move_mode_class: "arrangement-move-mode",
        arrangement_url_value: book_leaves_moves_url(book)
      }, &
  end

  def book_part_create_button(book, kind, **, &)
    url = url_for [ book, kind.new ]

    button_to url, class: "btn btn--plain txt-medium fill-transparent disable-when-arranging disable-when-deleting", draggable: true,
      data: {
        action: "dragstart->arrangement#dragStartCreate dragend->arrangement#dragEndCreate",
        arrangement_url_param: url
      }, **, &
  end

  def link_to_first_leafable(leaves)
    if first_leaf = leaves.first
      link_to leafable_slug_path(first_leaf), data: hotkey_data_attributes("right"), class: "disable-when-arranging", hidden: true do
        tag.span(class: "btn") do
          image_tag("arrow-right.svg", aria: { hidden: true }, size: 24) + tag.span("Start reading", class: "for-screen-reader")
        end + tag.span(first_leaf.title, class: "overflow-ellipsis")
      end
    end
  end

  def link_to_previous_leafable(leaf, hotkey: true, for_edit: false)
    if previous_leaf = leaf.previous
      path = for_edit ? edit_leafable_path(previous_leaf) : leafable_slug_path(previous_leaf)
      link_to path, data: hotkey_data_attributes("left", enabled: hotkey), class: "btn" do
        image_tag("arrow-left.svg", aria: { hidden: true }, size: 24) + tag.span("Previous: #{ previous_leaf.title }", class: "for-screen-reader")
      end
    else
      link_to book_slug_path(leaf.book), data: hotkey_data_attributes("left", enabled: hotkey), class: "btn" do
        image_tag("arrow-left.svg", aria: { hidden: true }, size: 24) + tag.span("Table of contents: #{ leaf.book.title }", class: "for-screen-reader")
      end
    end
  end

  def link_to_next_leafable(leaf, hotkey: true, for_edit: false)
    if next_leaf = leaf.next
      path = for_edit ? edit_leafable_path(next_leaf) : leafable_slug_path(next_leaf)
      link_to path, data: hotkey_data_attributes("right", enabled: hotkey), class: "btn txt-medium min-width" do
        tag.span("Next: #{next_leaf.title }", class: "overflow-ellipsis") + image_tag("arrow-right.svg", aria: { hidden: true }, size: 24)
      end
    else
      link_to book_slug_path(leaf.book), data: hotkey_data_attributes("right", enabled: hotkey), class: "btn txt-medium" do
        tag.span("Table of contents: #{leaf.book.title }", class: "overflow-ellipsis") + image_tag("arrow-reverse.svg", aria: { hidden: true }, size: 24)
      end
    end
  end

  private
    def hotkey_data_attributes(key, enabled: true)
      if enabled
        { controller: "hotkey", action: "keydown.#{key}@document->hotkey#click touch:swipe-#{key}@window->hotkey#click" }
      end
    end
end
