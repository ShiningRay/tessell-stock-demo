require "tessell"

module StockDemo
  # Fixed 1280x800 logical layout. Every visual rectangle is derived from here
  # so the DSL hit-test tree and the painter share the same numbers.
  class Layout
    WIDTH       = 1280
    HEIGHT      =  800
    HEADER_H    =   58
    FOOTER_H    =   28
    PAD         =   16
    GAP         =   12
    LEFT_W      =  296
    CENTER_W    =  632
    RIGHT_W     =  296
    WATCH_ROW_H =   62
    WATCH_ROWS  =    8

    getter width : Int32
    getter height : Int32
    getter header : Tessell::Rect
    getter footer : Tessell::Rect
    getter watchlist : Tessell::Rect
    getter detail : Tessell::Rect
    getter chart : Tessell::Rect
    getter book : Tessell::Rect
    getter info : Tessell::Rect
    getter watch_rows_y : Float32
    getter watch_row_h : Float32

    def initialize(@width : Int32 = WIDTH, @height : Int32 = HEIGHT)
      @header = Tessell::Rect.new(0.0_f32, 0.0_f32, @width.to_f32, HEADER_H.to_f32)
      @footer = Tessell::Rect.new(0.0_f32, (@height - FOOTER_H).to_f32,
        @width.to_f32, FOOTER_H.to_f32)
      content_y = HEADER_H.to_f32 + PAD
      content_h = (@height - HEADER_H - FOOTER_H - PAD * 2).to_f32
      left_x = PAD.to_f32
      center_x = left_x + LEFT_W + GAP
      right_x = center_x + CENTER_W + GAP
      @watchlist = Tessell::Rect.new(left_x, content_y, LEFT_W.to_f32, content_h)
      @detail = Tessell::Rect.new(center_x, content_y, CENTER_W.to_f32, 122.0_f32)
      @chart = Tessell::Rect.new(center_x, content_y + 134.0_f32,
        CENTER_W.to_f32, content_h - 134.0_f32)
      @book = Tessell::Rect.new(right_x, content_y, RIGHT_W.to_f32, 392.0_f32)
      @info = Tessell::Rect.new(right_x, content_y + 404.0_f32,
        RIGHT_W.to_f32, content_h - 404.0_f32)
      @watch_rows_y = content_y + 76.0_f32
      @watch_row_h = WATCH_ROW_H.to_f32
    end

    def watch_row(index : Int32) : Tessell::Rect
      y = @watch_rows_y + index * @watch_row_h
      Tessell::Rect.new(@watchlist.origin.x + 8.0_f32, y,
        @watchlist.size.width - 16.0_f32, @watch_row_h - 4.0_f32)
    end

    def watch_row_at(y : Float32) : Int32?
      return nil if y < @watch_rows_y
      idx = ((y - @watch_rows_y) / @watch_row_h).floor.to_i
      return nil if idx < 0 || idx >= WATCH_ROWS
      idx
    end

    # Price plot inside the chart card (right gutter reserved for price labels).
    def price_plot : Tessell::Rect
      Tessell::Rect.new(@chart.origin.x + 18.0_f32, @chart.origin.y + 64.0_f32,
        @chart.size.width - 80.0_f32, 316.0_f32)
    end

    def volume_plot : Tessell::Rect
      Tessell::Rect.new(@chart.origin.x + 18.0_f32, @chart.origin.y + 394.0_f32,
        @chart.size.width - 80.0_f32, 118.0_f32)
    end

    def time_labels_y : Float32
      @chart.origin.y + 526.0_f32
    end

    def tab_intraday : Tessell::Rect
      Tessell::Rect.new(@chart.origin.x + 14.0_f32, @chart.origin.y + 6.0_f32,
        64.0_f32, 34.0_f32)
    end

    def tab_daily : Tessell::Rect
      Tessell::Rect.new(@chart.origin.x + 82.0_f32, @chart.origin.y + 6.0_f32,
        64.0_f32, 34.0_f32)
    end

    def breadth_rect : Tessell::Rect
      width = @watchlist.size.width - 32.0_f32
      Tessell::Rect.new(@watchlist.origin.x + 16.0_f32,
        @watchlist.max_y - 96.0_f32, width, 80.0_f32)
    end
  end
end
