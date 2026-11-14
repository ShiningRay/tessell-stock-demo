require "tessell"
require "tessell/render/gl/gl_backend"

module StockDemo
  # Batched axis-aligned / rotated quads for panels, grids, area fills and
  # chart strokes. One glBegin(GL_QUADS) per frame keeps the demo's software
  # GL path cheap even with hundreds of chart segments.
  class Painter
    private struct Quad
      getter x0 : Float32
      getter y0 : Float32
      getter x1 : Float32
      getter y1 : Float32
      getter x2 : Float32
      getter y2 : Float32
      getter x3 : Float32
      getter y3 : Float32
      getter color : UInt32

      def initialize(@x0, @y0, @x1, @y1, @x2, @y2, @x3, @y3, @color)
      end
    end

    @quads : Array(Quad)

    def initialize(capacity : Int32 = 4096)
      @quads = Array(Quad).new(capacity)
    end

    def reset : Nil
      @quads.clear
    end

    def quad(x0, y0, x1, y1, x2, y2, x3, y3, color : UInt32) : Nil
      @quads << Quad.new(x0, y0, x1, y1, x2, y2, x3, y3, color)
    end

    def rect(x : Float32, y : Float32, w : Float32, h : Float32,
             color : UInt32) : Nil
      x, w = {x + w, -w} if w < 0
      y, h = {y + h, -h} if h < 0
      return if w <= 0.0_f32 || h <= 0.0_f32
      quad(x, y, x + w, y, x + w, y + h, x, y + h, color)
    end

    def rect(rect : Tessell::Rect, color : UInt32) : Nil
      self.rect(rect.origin.x, rect.origin.y, rect.size.width,
        rect.size.height, color)
    end

    def stroke_rect(x : Float32, y : Float32, w : Float32, h : Float32,
                    color : UInt32, thickness : Float32 = 1.0_f32) : Nil
      rect(x, y, w, thickness, color)
      rect(x, y + h - thickness, w, thickness, color)
      rect(x, y, thickness, h, color)
      rect(x + w - thickness, y, thickness, h, color)
    end

    def stroke_rect(rect : Tessell::Rect, color : UInt32,
                    thickness : Float32 = 1.0_f32) : Nil
      stroke_rect(rect.origin.x, rect.origin.y, rect.size.width,
        rect.size.height, color, thickness)
    end

    def hline(x : Float32, y : Float32, w : Float32, color : UInt32,
              thickness : Float32 = 1.0_f32) : Nil
      rect(x, y, w, thickness, color)
    end

    def vline(x : Float32, y : Float32, h : Float32, color : UInt32,
              thickness : Float32 = 1.0_f32) : Nil
      rect(x, y, thickness, h, color)
    end

    def line(x0 : Float32, y0 : Float32, x1 : Float32, y1 : Float32,
             width : Float32, color : UInt32) : Nil
      dx = x1 - x0
      dy = y1 - y0
      len = Math.sqrt(dx * dx + dy * dy)
      return if len < 0.0001_f32
      nx = -dy / len * width * 0.5_f32
      ny = dx / len * width * 0.5_f32
      quad(x0 + nx, y0 + ny, x1 + nx, y1 + ny,
        x1 - nx, y1 - ny, x0 - nx, y0 - ny, color)
    end

    def polyline(points : Array(Tessell::Point), width : Float32,
                 color : UInt32) : Nil
      i = 1
      while i < points.size
        a = points[i - 1]
        b = points[i]
        line(a.x, a.y, b.x, b.y, width, color)
        i += 1
      end
    end

    def dashed_hline(x0 : Float32, x1 : Float32, y : Float32,
                     color : UInt32, dash : Float32 = 4.0_f32,
                     gap : Float32 = 4.0_f32,
                     thickness : Float32 = 1.0_f32) : Nil
      x = x0
      while x < x1
        seg = Math.min(dash, x1 - x)
        rect(x, y, seg, thickness, color)
        x += dash + gap
      end
    end

    # Draw all collected quads. Leaves GL in the state the text renderer
    # expects (GL_TEXTURE_2D on, premultiplied blend function restored).
    def draw : Nil
      return if @quads.empty?
      TessellGL.glDisable(TessellGL::GL_TEXTURE_2D)
      TessellGL.glBlendFunc(TessellGL::GL_SRC_ALPHA,
        TessellGL::GL_ONE_MINUS_SRC_ALPHA)
      TessellGL.glBegin(TessellGL::GL_QUADS)
      @quads.each do |q|
        set_color(q.color)
        TessellGL.glVertex2f(q.x0, q.y0)
        TessellGL.glVertex2f(q.x1, q.y1)
        TessellGL.glVertex2f(q.x2, q.y2)
        TessellGL.glVertex2f(q.x3, q.y3)
      end
      TessellGL.glEnd
      TessellGL.glBlendFunc(TessellGL::GL_ONE,
        TessellGL::GL_ONE_MINUS_SRC_ALPHA)
      TessellGL.glEnable(TessellGL::GL_TEXTURE_2D)
    end

    def quad_count : Int32
      @quads.size
    end

    private def set_color(color : UInt32) : Nil
      r = ((color >> 24) & 0xff).to_f32 / 255.0_f32
      g = ((color >> 16) & 0xff).to_f32 / 255.0_f32
      b = ((color >> 8) & 0xff).to_f32 / 255.0_f32
      a = (color & 0xff).to_f32 / 255.0_f32
      TessellGL.glColor4f(r, g, b, a)
    end
  end
end
