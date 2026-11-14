require "tessell"

module StockDemo
  # Thin text helper on top of Tessell's shaped-run cache. Keeps a width cache
  # so right/centre alignment does not re-shape every label every frame.
  class TextLayer
    @sink : Array(Tessell::Text::GlyphPlacement)
    @widths : Hash(Tuple(String, Int32), Float32)

    def initialize(@renderer : Tessell::Render::TextRenderer,
                   @measurer : Tessell::Text::FtMeasurer,
                   @viewport_w : Int32, @viewport_h : Int32)
      @sink = [] of Tessell::Text::GlyphPlacement
      @widths = Hash(Tuple(String, Int32), Float32).new(2048)
    end

    def reset : Nil
      @renderer.reset
    end

    def text(x : Float32, center_y : Float32, size : Int32,
             color : UInt32, string : String) : Nil
      baseline = center_y + size.to_f32 * 0.36_f32
      @renderer.append_text_cached(@sink, string, x, baseline, size,
        @viewport_w, @viewport_h, color)
    end

    def text_baseline(x : Float32, baseline_y : Float32, size : Int32,
                      color : UInt32, string : String) : Nil
      @renderer.append_text_cached(@sink, string, x, baseline_y, size,
        @viewport_w, @viewport_h, color)
    end

    def right(right_x : Float32, center_y : Float32, size : Int32,
              color : UInt32, string : String) : Nil
      text(right_x - width(string, size), center_y, size, color, string)
    end

    def center(center_x : Float32, center_y : Float32, size : Int32,
               color : UInt32, string : String) : Nil
      text(center_x - width(string, size) * 0.5_f32, center_y, size, color, string)
    end

    def width(string : String, size : Int32) : Float32
      key = {string, size}
      if cached = @widths[key]?
        return cached
      end
      measured = @measurer.measure(string, 0, size.to_f32, 0.0_f32).width
      @widths.clear if @widths.size > 6000
      @widths[key] = measured
      measured
    end

    def renderer : Tessell::Render::TextRenderer
      @renderer
    end
  end
end
