class PdfPicture
  COLORSPACE_MAP = { DeviceRGB: "rgb", DeviceGray: "gray", DeviceCMYK: "cmyk" }.freeze

  def self.extract_from(page)
    new(page).extract
  end

  def initialize(page)
    @source = page
  end

  def extract
    @source.xobjects.flat_map do |name, stream|
      stream.hash[:Subtype] == :Image ? [ attachment_for(stream, name) ].compact : []
    end
  rescue => e
    Rails.logger.warn "PDF picture extraction failed: #{e.message}"
    []
  end

  private
    def attachment_for(stream, name)
      filter = Array(stream.hash[:Filter]).first

      case filter
      when :DCTDecode then jpeg_attachment(stream, name)
      when :JPXDecode then jp2_to_jpeg(stream, name)
      else                 raw_to_png(stream, name)
      end
    rescue => e
      Rails.logger.warn "PDF picture attachment failed for #{name}: #{e.message}"
      nil
    end

    def jpeg_attachment(stream, name)
      { io: StringIO.new(stream.data), filename: "#{name}.jpg", content_type: "image/jpeg" }
    end

    def jp2_to_jpeg(stream, name)
      jpeg_data = Tempfile.create([ name.to_s, ".jp2" ], binmode: true) do |f|
        f.write(stream.data)
        f.flush
        MiniMagick::Tool::Convert.new do |cmd|
          cmd << f.path
          cmd << "jpeg:-"
        end
      end

      { io: StringIO.new(jpeg_data), filename: "#{name}.jpg", content_type: "image/jpeg" }
    rescue => e
      Rails.logger.warn "PDF JP2 conversion failed for #{name}: #{e.message}"
      nil
    end

    def raw_to_png(stream, name)
      width      = stream.hash[:Width]
      height     = stream.hash[:Height]
      bit_depth  = stream.hash[:BitsPerComponent] || 8
      colorspace = COLORSPACE_MAP[stream.hash[:ColorSpace]]

      return nil unless width && height && colorspace

      png_data = Tempfile.create([ name.to_s, ".raw" ], binmode: true) do |raw_file|
        raw_file.write(stream.unfiltered_data)
        raw_file.flush

        MiniMagick::Tool::Convert.new do |cmd|
          cmd.size "#{width}x#{height}"
          cmd.depth bit_depth.to_s
          cmd << "#{colorspace}:#{raw_file.path}"
          cmd << "png:-"
        end
      end

      { io: StringIO.new(png_data), filename: "#{name}.png", content_type: "image/png" }
    rescue => e
      Rails.logger.warn "PDF raw picture conversion failed for #{name}: #{e.message}"
      nil
    end
end
