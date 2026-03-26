# The pdf-reader gem uses `font_size * 0.2` to decide whether a gap between
# two text runs should become a space. For large/bold fonts this threshold is
# too high and causes word spaces to be dropped (e.g. "Table Of Contents" →
# "TableOfContents"). Patching with 0.1 keeps tight intra-word kerning gap-free
# while still inserting spaces for typical word spacing in large fonts.
PDF::Reader::TextRun.prepend(Module.new do
  def +(other)
    raise ArgumentError, "#{other} cannot be merged with this run" unless mergable?(other)
    if (other.x - endx) < (font_size * 0.1)
      self.class.new(x, y, other.endx - x, font_size, text + other.text)
    else
      self.class.new(x, y, other.endx - x, font_size, "#{text} #{other.text}")
    end
  end
end)
