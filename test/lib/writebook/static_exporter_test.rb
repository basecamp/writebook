require "test_helper"
require "tmpdir"

class Writebook::StaticExporterTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname.new(Dir.mktmpdir)
    # The library shows published books to logged-out visitors.
    books(:handbook).update!(published: true)
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "generates the library index, every book, and every leaf" do
    book = books(:handbook)
    result = Writebook::StaticExporter.new(@dir, host: "example.com").call

    assert File.exist?(@dir.join("index.html"))
    assert_includes @dir.join("index.html").read, "Handbook"

    book_dir = @dir.join(book.id.to_s, book.slug)
    assert File.exist?(book_dir.join("index.html")), "expected book table of contents"

    book.leaves.active.with_leafables.positioned.each do |leaf|
      leaf_file = book_dir.join(leaf.id.to_s, leaf.slug, "index.html")
      assert File.exist?(leaf_file), "expected leaf #{leaf_file}"
    end

    assert_equal 1, result.books
    assert_equal book.leaves.active.count, result.leaves
  end

  test "copies compiled assets and root static files" do
    Writebook::StaticExporter.new(@dir, host: "example.com").call

    assert File.directory?(@dir.join("assets"))
    assert_operator Dir.glob(@dir.join("assets", "**", "*.css").to_s).size, :>, 0
    assert File.exist?(@dir.join("favicon.svg"))
  end

  test "copies referenced image blobs" do
    book = books(:handbook)
    picture = leaves(:reading_picture)

    result = Writebook::StaticExporter.new(@dir, host: "example.com").call

    # The picture leaf references an ActiveStorage image; the exporter should
    # have fetched it and written the bytes into the output tree.
    picture_html = @dir.join(book.id.to_s, book.slug, picture.id.to_s, picture.slug, "index.html").read
    assert_match %r{/rails/active_storage/}, picture_html

    copied = Dir.glob(@dir.join("rails", "active_storage", "**", "*").to_s).select { |p| File.file?(p) }
    assert_operator copied.size, :>, 0, "expected copied image blobs under rails/active_storage"
    assert_operator File.size(copied.first), :>, 0, "image file should not be empty"
    assert_equal 0, result.resource_failures, "every referenced resource should be fetched"
  end

  test "strips the library sign-in link and rewrites host URLs to be relative" do
    Writebook::StaticExporter.new(@dir, host: "example.com").call

    html = @dir.join("index.html").read
    assert_not_includes html, "/session", "sign-in link should be stripped from the static library"
    assert_not_includes html, "https://example.com", "host URLs should be rewritten as root-relative"
  end

  test "renders the bookmark route per book and rewrites the library frame src" do
    book = books(:handbook)
    Writebook::StaticExporter.new(@dir, host: "example.com").call

    # The bookmark frame the library cards auto-fetch is rendered to a static
    # file at books/<id>/bookmark/ -- matching the frame's src="/books/<id>/bookmark/"
    # (the route is keyed on the book id, not its slug) -- so the overlay click
    # target resolves instead of 404ing.
    bookmark_file = @dir.join("books", book.id.to_s, "bookmark", "index.html")
    assert File.exist?(bookmark_file), "expected bookmark file for the library cards"

    bookmark_html = bookmark_file.read
    assert_includes bookmark_html, "bookmark__link", "bookmark overlay link should be present"
    assert_includes bookmark_html, "/#{book.id}/#{book.slug}", "bookmark should link to the book"

    # The library index points the frame at the directory (trailing slash) so
    # the static host serves index.html with no redirect.
    library_html = @dir.join("index.html").read
    assert_includes library_html, %(src="/books/#{book.id}/bookmark/"),
      "library bookmark frame src should point at the static directory"
    assert_not_includes library_html, %(src="/books/#{book.id}/bookmark"),
      "library bookmark frame src should not be the bare route"
  end

  test "externalizes the per-book sidebar into a shared fetched fragment" do
    book = books(:handbook)
    Writebook::StaticExporter.new(@dir, host: "example.com").call

    book_dir = @dir.join(book.id.to_s, book.slug)

    # The full table of contents is written once per book, not copied into
    # every leaf.
    sidebar_file = book_dir.join("_sidebar.html")
    assert File.exist?(sidebar_file), "expected a shared sidebar fragment per book"
    sidebar_html = sidebar_file.read
    assert_includes sidebar_html, %(id="sidebar"), "shared sidebar should keep its aside id"
    assert_includes sidebar_html, "Summary", "shared sidebar should carry the leaf TOC links"

    # Each leaf carries a placeholder and a fetch of the shared fragment, not
    # the inline TOC. The fetch target is relative (../../_sidebar.html) and is
    # resolved against the leaf's own directory via a pathname normalization, so
    # the same export works at a domain root and under a subpath. A root-relative
    # /<book>/<slug>/_sidebar.html would 404 under any subpath, so guard against
    # regressing to that form.
    leaf = book.leaves.active.with_leafables.positioned.first
    leaf_html = book_dir.join(leaf.id.to_s, leaf.slug, "index.html").read
    assert_includes leaf_html, "data-static-sidebar-placeholder",
      "leaf should carry the sidebar placeholder"
    assert_includes leaf_html, "../../_sidebar.html",
      "leaf should fetch the shared sidebar two levels up, relative to the leaf"
    assert_includes leaf_html, "location.pathname",
      "leaf should normalize the pathname before resolving the relative fetch"
    assert_not_includes leaf_html, %(fetch("/#{book.id}/#{book.slug}/_sidebar.html")),
      "leaf must not use a root-relative sidebar fetch (breaks subpath hosting)"
    assert_not_includes leaf_html, %(<menu class="sidebar__content toc),
      "leaf should not embed the inline table of contents"
  end

  test "renders the markdown alternate for each book and leaf so the alternate link resolves" do
    book = books(:handbook)
    Writebook::StaticExporter.new(@dir, host: "example.com").call

    book_dir = @dir.join(book.id.to_s, book.slug)

    # The book view's <link rel="alternate" type="text/markdown"
    # href="/<id>/<slug>.md"> points at a file that lives next to the book's
    # own directory.
    book_md = book_dir.join("../#{book.slug}.md")
    assert File.exist?(book_md), "expected book markdown alternate #{book_md}"
    book_md_text = book_md.read
    assert_match(/\A---/, book_md_text, "book markdown should start with front-matter")
    assert_match(/^title:/, book_md_text, "book markdown should carry a front-matter title")

    # Each leaf view's alternate points at <id>/<slug>/<leaf_id>/<leaf_slug>.md,
    # living next to the leaf's <leaf_slug>/ directory.
    leaf = book.leaves.active.with_leafables.positioned.first
    leaf_md = book_dir.join(leaf.id.to_s, "#{leaf.slug}.md")
    assert File.exist?(leaf_md), "expected leaf markdown alternate #{leaf_md}"
    assert_match(/^url:/, leaf_md.read, "leaf markdown should carry a front-matter url")

    # The href the leaf HTML actually declares must resolve to a real file,
    # so the alternate link does not 404 on the static host.
    leaf_html = book_dir.join(leaf.id.to_s, leaf.slug, "index.html").read
    href = leaf_html[%r{<link rel="alternate"[^>]*href="([^"]+\.md)"}, 1]
    assert href, "leaf HTML should declare a markdown alternate link"
    assert File.exist?(@dir.join(href.delete_prefix("/"))),
      "the declared markdown alternate #{href} should resolve to a static file"
  end
end