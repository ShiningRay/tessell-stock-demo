require "time"
require "tessell"
require "tessell/render/gl/gl_backend"
require "./market"
require "./theme"
require "./layout"
require "./painter"
require "./text_layer"
require "./shot"

module StockDemo
  enum View
    Intraday
    Daily
  end

  # The terminal application. Owns the simulated feed, the retained DSL tree
  # used for hit testing, and the self-drawn renderer.
  class App
    getter market : Market
    getter selected : Int32
    getter view : View
    getter dark : Bool
    getter paused : Bool
    getter frame_count : Int32
    getter last_quad_count : Int32
    getter last_text_quads : Int32

    @palette : Palette
    @layout : Layout
    @tick_interval_ms : Int32
    @last_tick_ms : Float64
    @hover_row : Int32?
    @hover_tab : Int32?
    @quit_requested : Bool

    @measurer : Tessell::Text::FtMeasurer
    @atlas : Tessell::Text::GlyphAtlas
    @rasterizer : Tessell::Text::Rasterizer
    @renderer : Tessell::Render::TextRenderer
    @backend : Tessell::Render::GL::GLBackend
    @painter : Painter
    @text : TextLayer
    @synced_pages : Int32
    @synced_pixels : Int32
    @synced_evictions : Int32

    @root : Tessell::Node
    @pool : Tessell::UI::Pool
    @builder : Tessell::UI::Builder
    @dirty_sink : Array(Tessell::Node)
    @router : Tessell::Input::Router
    @row_keys : Array(Tessell::UI::UiKey)
    @row_nodes : Array(Tessell::Node?)
    @tab_intraday_key : Tessell::UI::UiKey
    @tab_daily_key : Tessell::UI::UiKey
    @tab_intraday_node : Tessell::Node?
    @tab_daily_node : Tessell::Node?
    @candle_dates : Array(String)

    def initialize(seed : UInt64 = 20_261_114_u64, warmup : Int32 = 0,
                   dark : Bool = true, tick_ms : Int32 = 500,
                   font_path : String = "C:/Windows/Fonts/msyh.ttc")
      @market = Market.new(seed: seed, start_minute: 150)
      @market.warmup(warmup)
      @selected = 0
      @view = View::Intraday
      @dark = dark
      @paused = false
      @palette = dark ? Palette.dark : Palette.light
      @layout = Layout.new
      @tick_interval_ms = tick_ms.clamp(50, 10_000)
      @last_tick_ms = -1.0
      @hover_row = nil
      @hover_tab = nil
      @quit_requested = false
      @frame_count = 0
      @last_quad_count = 0
      @last_text_quads = 0

      @measurer = Tessell::Text::FtMeasurer.open(font_path, 0)
      @atlas = Tessell::Text::GlyphAtlas.new(1024, 4096)
      @rasterizer = Tessell::Text::Rasterizer.new(@measurer, @atlas, 0, 1024)
      @renderer = Tessell::Render::TextRenderer.new(@atlas, @rasterizer)
      @backend = Tessell::Render::GL::GLBackend.new
      @backend.init(@layout.width, @layout.height)
      @backend.resize(@layout.width, @layout.height)
      @renderer.reserve_quads(16_384)
      @renderer.reserve_batches(1024)
      @painter = Painter.new(12_000)
      @text = TextLayer.new(@renderer, @measurer, @layout.width, @layout.height)
      @synced_pages = -1
      @synced_pixels = -1
      @synced_evictions = -1

      @root = Tessell::Node.new("root",
        Tessell::Rect.new(0.0_f32, 0.0_f32,
          @layout.width.to_f32, @layout.height.to_f32))
      @pool = Tessell::UI::Pool.new
      @builder = Tessell::UI::Builder.new(
        [] of Tessell::UI::Decl, [] of Tessell::UI::UiKey)
      @dirty_sink = [] of Tessell::Node
      @router = Tessell::Input::Router.new

      @row_keys = Array(Tessell::UI::UiKey).new(Layout::WATCH_ROWS)
      Layout::WATCH_ROWS.times do |i|
        @row_keys << Tessell::UI::UiKey.root.child(1000_u64 + i.to_u64)
      end
      @row_nodes = Array(Tessell::Node?).new(Layout::WATCH_ROWS, nil)
      @tab_intraday_key = Tessell::UI::UiKey.root.child(200_u64)
      @tab_daily_key = Tessell::UI::UiKey.root.child(201_u64)
      @tab_intraday_node = nil
      @tab_daily_node = nil

      @candle_dates = Array(String).new(300)
      today = Time.utc(2026, 11, 14)
      300.times do |i|
        @candle_dates << (today - (299 - i).days).to_s("%m-%d")
      end

      build_ui
      Tessell::UI.apply(@builder.buf, @root, @pool)
      @dirty_sink.clear
      Tessell::Node.collect_dirty(@root, @dirty_sink)
      Tessell::UI.consume(@dirty_sink)
      refresh_nodes
    end

    def quit_requested? : Bool
      @quit_requested
    end

    # ---- state / input -----------------------------------------------------

    def current_stock : Stock
      @market.stocks[@selected]
    end

    def select_stock(index : Int32) : Nil
      return if @market.stocks.empty?
      @selected = index.clamp(0, @market.stocks.size - 1)
    end

    def select_delta(delta : Int32) : Nil
      select_stock(@selected + delta)
    end

    def toggle_theme : Nil
      @dark = !@dark
      @palette = @dark ? Palette.dark : Palette.light
    end

    def toggle_view : Nil
      @view = @view == View::Intraday ? View::Daily : View::Intraday
    end

    def view=(value : View) : Nil
      @view = value
    end

    def toggle_pause : Nil
      @paused = !@paused
    end

    def handle_vk(vk : UInt32) : Nil
      case vk
      when 0x1b_u32 then @quit_requested = true
      when 0x26_u32 then select_delta(-1)
      when 0x28_u32 then select_delta(1)
      when 0x43_u32 then toggle_view
      when 0x4b_u32 then toggle_view
      when 0x54_u32 then toggle_theme
      when 0x20_u32 then toggle_pause
      else
        if vk >= 0x31_u32 && vk <= 0x38_u32
          select_stock((vk - 0x31_u32).to_i)
        end
      end
    end

    def handle_pointer_down(x : Float32, y : Float32) : Nil
      target = @router.handle(Tessell::Input::Event.pointer_down(x, y), @root)
      return unless target
      @row_nodes.each_with_index do |node, i|
        if node == target
          select_stock(i)
          return
        end
      end
      if target == @tab_intraday_node
        @view = View::Intraday
      elsif target == @tab_daily_node
        @view = View::Daily
      end
    end

    def handle_pointer_move(x : Float32, y : Float32) : Nil
      hover = @router.handle(Tessell::Input::Event.pointer_move(x, y), @root)
      @hover_row = nil
      @hover_tab = nil
      @row_nodes.each_with_index do |node, i|
        @hover_row = i if node == hover
      end
      @hover_tab = 0 if hover == @tab_intraday_node
      @hover_tab = 1 if hover == @tab_daily_node
    end

    def update(now_ms : Float64) : Nil
      if @last_tick_ms < 0.0
        @last_tick_ms = now_ms
        return
      end
      if @paused
        @last_tick_ms = now_ms
        return
      end
      if now_ms - @last_tick_ms >= @tick_interval_ms
        @market.tick
        @last_tick_ms = now_ms
      end
    end

    # ---- DSL hit-test tree -------------------------------------------------

    private def build_ui : Nil
      layout = @layout
      Tessell::UI.build(Tessell::UI::UiKey.root, @builder) do |b|
        b.node(Tessell::UI::UiKey.root.child(1_u64), layout.watchlist)
        b.node(Tessell::UI::UiKey.root.child(2_u64), layout.detail)
        b.node(Tessell::UI::UiKey.root.child(3_u64), layout.chart)
        b.node(Tessell::UI::UiKey.root.child(4_u64), layout.book)
        b.node(Tessell::UI::UiKey.root.child(5_u64), layout.info)
        @row_keys.each_with_index do |key, i|
          b.node(key, layout.watch_row(i))
        end
        b.node(@tab_intraday_key, layout.tab_intraday)
        b.node(@tab_daily_key, layout.tab_daily)
      end
    end

    private def refresh_nodes : Nil
      @row_nodes.clear
      @row_keys.each do |key|
        @row_nodes << @pool.map[key]?
      end
      @tab_intraday_node = @pool.map[@tab_intraday_key]?
      @tab_daily_node = @pool.map[@tab_daily_key]?
    end

    # ---- frame -------------------------------------------------------------

    def run_frame(now_ms : Float64) : Nil
      update(now_ms)
      @frame_count += 1
      build_ui
      Tessell::UI.apply(@builder.buf, @root, @pool)
      @dirty_sink.clear
      Tessell::Node.collect_dirty(@root, @dirty_sink)
      Tessell::UI.consume(@dirty_sink)
      refresh_nodes

      @painter.reset
      @text.reset
      compose
      sync_atlas_if_needed

      theme = Tessell::Render::Theme.new(@palette.bg, @palette.text,
        @palette.accent, @palette.muted, @palette.border,
        @palette.accent_soft)
      @backend.begin_frame(nil, theme)
      @painter.draw
      @last_quad_count = @painter.quad_count
      @backend.draw_text(@renderer.vertices, @renderer.batch_runs,
        @renderer.batch_count)
      @last_text_quads = @renderer.stats[:quads]
      @backend.end_frame
    end

    def capture(path : String) : Nil
      Shot.save(path, @layout.width, @layout.height)
    end

    def dispose : Nil
      @backend.delete_textures
      @measurer.close
    end

    def stats_line : String
      stock = current_stock
      "frames=#{@frame_count} theme=#{@dark ? "dark" : "light"} " \
      "seed=#{@market.seed} minute=#{@market.minute} day=#{@market.day} " \
      "symbol=#{stock.code} price=#{Fmt.price(stock.price)} " \
      "quads=#{@last_quad_count} text_quads=#{@last_text_quads} " \
      "view=#{@view} paused=#{@paused}"
    end

    private def sync_atlas_if_needed : Nil
      pages = @atlas.page_count
      pixels = @atlas.used_pixels
      evictions = @atlas.evicted_total
      return if pages == @synced_pages && pixels == @synced_pixels &&
                evictions == @synced_evictions
      @backend.sync_atlas(@atlas)
      @synced_pages = pages
      @synced_pixels = pixels
      @synced_evictions = evictions
    end

    # ---- composition -------------------------------------------------------

    private def compose : Nil
      stock = current_stock
      draw_shell
      draw_header
      draw_watchlist
      draw_detail(stock)
      draw_chart(stock)
      draw_book(stock)
      draw_info(stock)
      draw_footer
    end

    private def draw_shell : Nil
      @painter.rect(@layout.header, @palette.panel)
      @painter.hline(0.0_f32, (Layout::HEADER_H - 1).to_f32,
        @layout.width.to_f32, @palette.border)
      @painter.rect(@layout.footer, @palette.panel)
      @painter.hline(0.0_f32, @layout.footer.origin.y,
        @layout.width.to_f32, @palette.border)
      panel(@layout.watchlist)
      panel(@layout.detail)
      panel(@layout.chart)
      panel(@layout.book)
      panel(@layout.info)
    end

    private def panel(rect : Tessell::Rect) : Nil
      @painter.rect(rect, @palette.panel)
      @painter.stroke_rect(rect, @palette.border)
    end

    private def draw_header : Nil
      @painter.rect(24.0_f32, 18.0_f32, 3.0_f32, 22.0_f32, @palette.accent)
      @text.text(36.0_f32, 26.0_f32, 18, @palette.text, "TESSEL")
      logo_w = @text.width("TESSEL", 18)
      @text.text(36.0_f32 + logo_w + 6.0_f32, 26.0_f32, 18,
        @palette.accent, "行情")
      @text.text(36.0_f32, 44.0_f32, 10, @palette.muted,
        "A 股模拟行情终端 · Crystal / OpenGL")

      @painter.vline(324.0_f32, 14.0_f32, 30.0_f32, @palette.border)

      x = 344.0_f32
      @market.indices.each do |index|
        card = Tessell::Rect.new(x, 10.0_f32, 152.0_f32, 38.0_f32)
        @painter.rect(card, @palette.card)
        @painter.stroke_rect(card, @palette.border)
        @text.text(x + 12.0_f32, 21.0_f32, 10, @palette.muted, index.name)
        @text.text(x + 12.0_f32, 39.0_f32, 14, @palette.text,
          Fmt.price(index.value))
        @text.right(x + 140.0_f32, 39.0_f32, 10,
          trend_color(index.change), Fmt.pct(index.change_pct))
        x += 164.0_f32
      end

      pill_w = 64.0_f32
      pill_x = 1192.0_f32
      if @paused
        @painter.rect(pill_x, 12.0_f32, pill_w, 22.0_f32,
          Palette.alpha(@palette.amber, 0x22_u8))
        @painter.rect(pill_x + 10.0_f32, 20.0_f32, 6.0_f32, 6.0_f32,
          @palette.amber)
        @text.text(pill_x + 20.0_f32, 23.0_f32, 9, @palette.amber, "PAUSED")
      else
        @painter.rect(pill_x, 12.0_f32, pill_w, 22.0_f32,
          @palette.accent_soft)
        @painter.rect(pill_x + 10.0_f32, 20.0_f32, 6.0_f32, 6.0_f32,
          @palette.up)
        @text.text(pill_x + 20.0_f32, 23.0_f32, 9, @palette.accent, "LIVE")
      end
      @text.right(1264.0_f32, 43.0_f32, 10, @palette.muted,
        "模拟 #{Fmt.clock(@market.minute, @market.clock_second)}")
    end

    private def draw_watchlist : Nil
      rect = @layout.watchlist
      left = rect.origin.x
      top = rect.origin.y
      right = rect.max_x
      @text.text(left + 18.0_f32, top + 28.0_f32, 15, @palette.text, "自选股")
      @text.right(right - 18.0_f32, top + 28.0_f32, 10, @palette.muted,
        "#{@market.stocks.size} 只")
      @painter.hline(left + 16.0_f32, top + 52.0_f32,
        rect.size.width - 32.0_f32, @palette.grid)
      @text.text(left + 18.0_f32, top + 64.0_f32, 9, @palette.faint,
        "名称 / 代码")
      @text.right(left + 222.0_f32, top + 64.0_f32, 9, @palette.faint, "最新")
      @text.right(right - 18.0_f32, top + 64.0_f32, 9, @palette.faint, "涨跌幅")

      @market.stocks.each_with_index do |stock, i|
        row = @layout.watch_row(i)
        selected = i == @selected
        hovered = @hover_row == i
        if selected
          @painter.rect(row, @palette.panel_alt)
          @painter.rect(left + 8.0_f32, row.origin.y + 5.0_f32, 3.0_f32,
            row.size.height - 10.0_f32, @palette.accent)
        elsif hovered
          @painter.rect(row, @palette.card)
        end
        @painter.hline(left + 16.0_f32, row.max_y + 2.0_f32,
          rect.size.width - 32.0_f32, @palette.grid)

        color = trend_color(stock.change)
        @text.text(row.origin.x + 12.0_f32, row.origin.y + 20.0_f32, 14,
          @palette.text, stock.name)
        @text.text(row.origin.x + 12.0_f32, row.origin.y + 43.0_f32, 9,
          @palette.muted, "#{stock.code} · #{stock.market}")
        draw_sparkline(stock, row.origin.x + 108.0_f32,
          row.origin.y + 19.0_f32, 62.0_f32, 24.0_f32, color)
        @text.right(row.max_x - 8.0_f32, row.origin.y + 20.0_f32, 14,
          color, Fmt.price(stock.price))
        @text.right(row.max_x - 8.0_f32, row.origin.y + 43.0_f32, 11,
          color, Fmt.pct(stock.change_pct))
      end

      draw_breadth
    end

    private def draw_breadth : Nil
      area = @layout.breadth_rect
      @painter.hline(area.origin.x, area.origin.y - 8.0_f32,
        area.size.width, @palette.grid)
      @text.text(area.origin.x, area.origin.y + 4.0_f32, 10,
        @palette.muted, "市场广度")
      up = @market.up_count
      down = @market.down_count
      flat = @market.flat_count
      @text.text(area.origin.x, area.origin.y + 24.0_f32, 10,
        @palette.up, "上涨 #{up}")
      @text.text(area.origin.x + 62.0_f32, area.origin.y + 24.0_f32, 10,
        @palette.down, "下跌 #{down}")
      @text.text(area.origin.x + 124.0_f32, area.origin.y + 24.0_f32, 10,
        @palette.muted, "平 #{flat}")

      bar_y = area.origin.y + 40.0_f32
      bar_w = area.size.width
      @painter.rect(area.origin.x, bar_y, bar_w, 6.0_f32, @palette.grid)
      total = [up + down + flat, 1].max
      up_w = bar_w * up.to_f32 / total.to_f32
      down_w = bar_w * down.to_f32 / total.to_f32
      @painter.rect(area.origin.x, bar_y, up_w, 6.0_f32, @palette.up)
      @painter.rect(area.origin.x + up_w, bar_y, down_w, 6.0_f32,
        @palette.down)
      @text.text(area.origin.x, area.origin.y + 62.0_f32, 9,
        @palette.faint, "↑↓ 切换 · 点击选择 · 数字键 1-8")
    end

    private def draw_sparkline(stock : Stock, x : Float32, y : Float32,
                               w : Float32, h : Float32, color : UInt32) : Nil
      points = stock.points
      n = Math.min(24, points.size)
      return if n < 2
      first = points.size - n
      min = points[first].price
      max = min
      i = first + 1
      while i < points.size
        price = points[i].price
        min = price if price < min
        max = price if price > max
        i += 1
      end
      span = max - min
      span = 1.0 if span <= 0.0
      i = 1
      while i < n
        a = points[first + i - 1].price
        b = points[first + i].price
        x0 = x + (i - 1).to_f32 / (n - 1).to_f32 * w
        x1 = x + i.to_f32 / (n - 1).to_f32 * w
        y0 = y + h - ((a - min) / span).to_f32 * h
        y1 = y + h - ((b - min) / span).to_f32 * h
        @painter.line(x0, y0, x1, y1, 1.2_f32, color)
        i += 1
      end
    end

    private def draw_detail(stock : Stock) : Nil
      rect = @layout.detail
      x = rect.origin.x
      y = rect.origin.y
      color = trend_color(stock.change)

      @text.text(x + 22.0_f32, y + 28.0_f32, 21, @palette.text, stock.name)
      name_w = @text.width(stock.name, 21)
      tag_x = x + 22.0_f32 + name_w + 10.0_f32
      @painter.rect(tag_x, y + 18.0_f32, 32.0_f32, 18.0_f32,
        @palette.accent_soft)
      @text.center(tag_x + 16.0_f32, y + 27.0_f32, 9, @palette.accent,
        stock.market)
      @text.text(x + 22.0_f32, y + 54.0_f32, 10, @palette.muted,
        "#{stock.code} · 模拟实时行情")

      @text.text(x + 22.0_f32, y + 93.0_f32, 40, color,
        Fmt.price(stock.price))
      price_w = @text.width(Fmt.price(stock.price), 40)
      @text.text(x + 22.0_f32 + price_w + 16.0_f32, y + 92.0_f32, 13,
        color, "#{Fmt.signed_price(stock.change)}  #{Fmt.pct(stock.change_pct)}")

      @painter.vline(x + 340.0_f32, y + 18.0_f32, rect.size.height - 36.0_f32,
        @palette.grid)

      pairs = [
        {"今开", Fmt.price(stock.open)},
        {"最高", Fmt.price(stock.high)},
        {"最低", Fmt.price(stock.low)},
        {"昨收", Fmt.price(stock.prev_close)},
        {"成交量", Fmt.volume(stock.volume)},
        {"成交额", Fmt.amount(stock.turnover)},
      ]
      col_x = [x + 360.0_f32, x + 494.0_f32]
      row_y = y + 24.0_f32
      pairs.each_with_index do |pair, i|
        cx = col_x[i % 2]
        cy = row_y + (i // 2) * 27.0_f32
        @text.text(cx, cy, 9, @palette.muted, pair[0])
        @text.right(cx + 118.0_f32, cy, 11, @palette.text, pair[1])
      end
    end

    private def draw_chart(stock : Stock) : Nil
      rect = @layout.chart
      x = rect.origin.x
      y = rect.origin.y

      draw_tab(@layout.tab_intraday, "分时", @view == View::Intraday,
        @hover_tab == 0)
      draw_tab(@layout.tab_daily, "日K", @view == View::Daily,
        @hover_tab == 1)

      if @view == View::Intraday
        @text.text(x + 430.0_f32, y + 21.0_f32, 9, @palette.muted, "均价")
        @text.text(x + 462.0_f32, y + 21.0_f32, 10, @palette.amber,
          Fmt.price(stock.avg_price))
      else
        ma5 = moving_average(stock.candles, 5)
        ma10 = moving_average(stock.candles, 10)
        @text.text(x + 402.0_f32, y + 21.0_f32, 9, @palette.muted, "MA5")
        @text.text(x + 430.0_f32, y + 21.0_f32, 10, @palette.amber,
          Fmt.price(ma5))
        @text.text(x + 484.0_f32, y + 21.0_f32, 9, @palette.muted, "MA10")
        @text.text(x + 518.0_f32, y + 21.0_f32, 10, @palette.purple,
          Fmt.price(ma10))
      end

      @painter.hline(x, y + 42.0_f32, rect.size.width, @palette.grid)
      if @view == View::Intraday
        draw_intraday_chart(stock)
      else
        draw_daily_chart(stock)
      end
    end

    private def draw_tab(rect : Tessell::Rect, label : String, active : Bool,
                         hovered : Bool) : Nil
      if active
        @painter.rect(rect, @palette.accent_soft)
      elsif hovered
        @painter.rect(rect, @palette.card)
      end
      color = active ? @palette.accent : @palette.muted
      @text.center(rect.origin.x + rect.size.width * 0.5_f32,
        rect.origin.y + rect.size.height * 0.5_f32, 11, color, label)
      if active
        @painter.rect(rect.origin.x + 12.0_f32, rect.max_y - 2.0_f32,
          rect.size.width - 24.0_f32, 2.0_f32, @palette.accent)
      end
    end

    private def draw_intraday_chart(stock : Stock) : Nil
      plot = @layout.price_plot
      volume = @layout.volume_plot
      points = stock.points
      return if points.empty?

      center = stock.prev_close
      up = Math.max(stock.high, center) - center
      down = center - Math.min(stock.low, center)
      span = Math.max(up, down) * 1.12
      span = Math.max(span, center * 0.004)
      low = center - span
      high = center + span
      color = trend_color(stock.change)

      draw_price_grid(plot, low, high)
      draw_time_grid(plot, volume)
      draw_time_labels(plot, ["09:30", "10:30", "11:30/13:00", "14:00", "15:00"])

      @painter.dashed_hline(plot.origin.x, plot.max_x,
        map_y(center, low, high, plot), @palette.faint, 3.0_f32, 5.0_f32,
        1.0_f32)

      # Soft area fill under the intraday line, one column at a time.
      cols = plot.size.width.to_i
      cx = 0
      while cx < cols
        idx = (cx.to_f32 / (cols - 1).to_f32 * 239.0_f32).round.to_i
        break if idx >= points.size
        y = map_y(points[idx].price, low, high, plot)
        @painter.rect(plot.origin.x + cx.to_f32, y, 1.0_f32,
          plot.max_y - y, Palette.alpha(color, 0x20_u8))
        cx += 1
      end

      draw_avg_line(points, plot, low, high)
      draw_price_line(points, plot, low, high, color)
      draw_last_dot(points, plot, low, high, color)
      draw_current_line(plot, stock.price, low, high, color)

      draw_volume_bars(points, volume)
      @text.text(@layout.chart.origin.x + 18.0_f32,
        volume.origin.y - 12.0_f32, 9, @palette.muted, "成交量")
    end

    private def draw_daily_chart(stock : Stock) : Nil
      plot = @layout.price_plot
      volume = @layout.volume_plot
      candles = stock.candles
      return if candles.empty?

      visible = Math.min(48, candles.size)
      start = candles.size - visible
      min = candles[start].low
      max = candles[start].high
      i = start
      while i < candles.size
        candle = candles[i]
        min = candle.low if candle.low < min
        max = candle.high if candle.high > max
        i += 1
      end
      pad = (max - min) * 0.08
      pad = max * 0.002 if pad <= 0.0
      min -= pad
      max += pad
      color = trend_color(stock.change)

      draw_price_grid(plot, min, max)
      draw_time_grid(plot, volume)
      draw_candle_labels(plot, start, visible, candles.size)

      step = plot.size.width / visible.to_f32
      body_w = Math.min(9.0_f32, step * 0.58_f32)
      i = 0
      while i < visible
        candle = candles[start + i]
        cx = plot.origin.x + (i.to_f32 + 0.5_f32) * step
        wick_color = candle.close >= candle.open ? @palette.up : @palette.down
        high_y = map_y(candle.high, min, max, plot)
        low_y = map_y(candle.low, min, max, plot)
        @painter.rect(cx - 0.5_f32, high_y, 1.0_f32,
          Math.max(1.0_f32, low_y - high_y), wick_color)
        body_top = map_y(Math.max(candle.open, candle.close), min, max, plot)
        body_bottom = map_y(Math.min(candle.open, candle.close), min, max, plot)
        @painter.rect(cx - body_w * 0.5_f32, body_top, body_w,
          Math.max(1.0_f32, body_bottom - body_top), wick_color)
        i += 1
      end

      draw_ma_line(candles, start, visible, 5, plot, min, max,
        @palette.amber)
      draw_ma_line(candles, start, visible, 10, plot, min, max,
        @palette.purple)
      draw_current_line(plot, stock.price, min, max, color)
      draw_candle_volume(candles, start, visible, volume)
      @text.text(@layout.chart.origin.x + 18.0_f32,
        volume.origin.y - 12.0_f32, 9, @palette.muted, "成交量")
    end

    private def draw_price_grid(plot : Tessell::Rect, low : Float64,
                                high : Float64) : Nil
      i = 0
      while i <= 4
        y = plot.origin.y + plot.size.height * i.to_f32 / 4.0_f32
        @painter.hline(plot.origin.x, y, plot.size.width, @palette.grid)
        value = high - (high - low) * i.to_f64 / 4.0
        @text.right(@layout.chart.max_x - 14.0_f32, y, 9,
          @palette.muted, Fmt.price(value))
        i += 1
      end
    end

    private def draw_time_grid(plot : Tessell::Rect,
                               volume : Tessell::Rect) : Nil
      i = 0
      while i <= 4
        x = plot.origin.x + plot.size.width * i.to_f32 / 4.0_f32
        @painter.vline(x, plot.origin.y,
          volume.max_y - plot.origin.y, @palette.grid)
        i += 1
      end
    end

    private def draw_time_labels(plot : Tessell::Rect,
                                 labels : Array(String)) : Nil
      y = @layout.time_labels_y
      labels.each_with_index do |label, i|
        if i == 0
          @text.text(plot.origin.x, y, 9, @palette.faint, label)
        elsif i == labels.size - 1
          @text.right(plot.max_x, y, 9, @palette.faint, label)
        else
          @text.center(plot.origin.x + plot.size.width * i.to_f32 / 4.0_f32,
            y, 9, @palette.faint, label)
        end
      end
    end

    private def draw_candle_labels(plot : Tessell::Rect, start : Int32,
                                   visible : Int32, total : Int32) : Nil
      y = @layout.time_labels_y
      indices = [0, visible // 4, visible // 2, visible * 3 // 4, visible - 1]
      offset = @candle_dates.size - total
      indices.each_with_index do |idx, i|
        cx = plot.origin.x + (idx.to_f32 + 0.5_f32) /
                             visible.to_f32 * plot.size.width
        label = @candle_dates[offset + start + idx]? || ""
        if i == 0
          @text.text(plot.origin.x, y, 9, @palette.faint, label)
        elsif i == indices.size - 1
          @text.right(plot.max_x, y, 9, @palette.faint, label)
        else
          @text.center(cx, y, 9, @palette.faint, label)
        end
      end
    end

    private def draw_price_line(points : Array(QuotePoint),
                                plot : Tessell::Rect, low : Float64,
                                high : Float64, color : UInt32) : Nil
      i = 1
      while i < points.size
        x0 = plot.origin.x + points[i - 1].minute.to_f32 / 239.0_f32 *
                             plot.size.width
        x1 = plot.origin.x + points[i].minute.to_f32 / 239.0_f32 *
                             plot.size.width
        y0 = map_y(points[i - 1].price, low, high, plot)
        y1 = map_y(points[i].price, low, high, plot)
        @painter.line(x0, y0, x1, y1, 1.8_f32, color)
        i += 1
      end
    end

    private def draw_avg_line(points : Array(QuotePoint),
                              plot : Tessell::Rect, low : Float64,
                              high : Float64) : Nil
      i = 1
      while i < points.size
        x0 = plot.origin.x + points[i - 1].minute.to_f32 / 239.0_f32 *
                             plot.size.width
        x1 = plot.origin.x + points[i].minute.to_f32 / 239.0_f32 *
                             plot.size.width
        y0 = map_y(points[i - 1].avg, low, high, plot)
        y1 = map_y(points[i].avg, low, high, plot)
        @painter.line(x0, y0, x1, y1, 1.0_f32,
          Palette.alpha(@palette.amber, 0xcc_u8))
        i += 1
      end
    end

    private def draw_last_dot(points : Array(QuotePoint),
                              plot : Tessell::Rect, low : Float64,
                              high : Float64, color : UInt32) : Nil
      last = points.last
      x = plot.origin.x + last.minute.to_f32 / 239.0_f32 * plot.size.width
      y = map_y(last.price, low, high, plot)
      @painter.rect(x - 2.5_f32, y - 2.5_f32, 5.0_f32, 5.0_f32, color)
    end

    private def draw_current_line(plot : Tessell::Rect, price : Float64,
                                  low : Float64, high : Float64,
                                  color : UInt32) : Nil
      y = map_y(price, low, high, plot)
      @painter.dashed_hline(plot.origin.x, plot.max_x, y,
        Palette.alpha(color, 0x70_u8), 4.0_f32, 4.0_f32, 1.0_f32)
    end

    private def draw_volume_bars(points : Array(QuotePoint),
                                 volume : Tessell::Rect) : Nil
      max_vol = 1_i64
      points.each { |p| max_vol = p.volume if p.volume > max_vol }
      bar_w = Math.max(1.0_f32, volume.size.width / 240.0_f32 * 0.62_f32)
      i = 0
      while i < points.size
        point = points[i]
        x = volume.origin.x + point.minute.to_f32 / 239.0_f32 *
                              volume.size.width
        h = (point.volume.to_f64 / max_vol.to_f64 * volume.size.height).to_f32
        up = i == 0 ? point.price >= @market.stocks[@selected].open : point.price >= points[i - 1].price
        color = up ? @palette.up : @palette.down
        @painter.rect(x - bar_w * 0.5_f32, volume.max_y - h, bar_w, h,
          Palette.alpha(color, 0xb0_u8))
        i += 1
      end
      @painter.hline(volume.origin.x, volume.max_y, volume.size.width,
        @palette.grid)
    end

    private def draw_candle_volume(candles : Array(Candle), start : Int32,
                                   visible : Int32,
                                   volume : Tessell::Rect) : Nil
      max_vol = 1_i64
      i = 0
      while i < visible
        vol = candles[start + i].volume
        max_vol = vol if vol > max_vol
        i += 1
      end
      step = volume.size.width / visible.to_f32
      bar_w = Math.max(1.0_f32, step * 0.58_f32)
      i = 0
      while i < visible
        candle = candles[start + i]
        x = volume.origin.x + (i.to_f32 + 0.5_f32) * step
        h = (candle.volume.to_f64 / max_vol.to_f64 * volume.size.height).to_f32
        color = candle.close >= candle.open ? @palette.up : @palette.down
        @painter.rect(x - bar_w * 0.5_f32, volume.max_y - h, bar_w, h,
          Palette.alpha(color, 0xb0_u8))
        i += 1
      end
      @painter.hline(volume.origin.x, volume.max_y, volume.size.width,
        @palette.grid)
    end

    private def draw_ma_line(candles : Array(Candle), start : Int32,
                             visible : Int32, period : Int32,
                             plot : Tessell::Rect, low : Float64,
                             high : Float64, color : UInt32) : Nil
      prev_x = 0.0_f32
      prev_y = 0.0_f32
      has_prev = false
      i = 0
      while i < visible
        global = start + i
        if global >= period - 1
          sum = 0.0
          j = global - period + 1
          while j <= global
            sum += candles[j].close
            j += 1
          end
          avg = sum / period
          x = plot.origin.x + (i.to_f32 + 0.5_f32) /
                              visible.to_f32 * plot.size.width
          y = map_y(avg, low, high, plot)
          if has_prev
            @painter.line(prev_x, prev_y, x, y, 1.1_f32, color)
          end
          prev_x = x
          prev_y = y
          has_prev = true
        end
        i += 1
      end
    end

    private def draw_book(stock : Stock) : Nil
      rect = @layout.book
      x = rect.origin.x
      y = rect.origin.y
      w = rect.size.width
      @text.text(x + 16.0_f32, y + 22.0_f32, 13, @palette.text, "五档盘口")
      @text.right(x + w - 16.0_f32, y + 22.0_f32, 9, @palette.faint,
        "模拟撮合")
      @painter.hline(x + 12.0_f32, y + 40.0_f32, w - 24.0_f32,
        @palette.grid)
      @text.text(x + 16.0_f32, y + 53.0_f32, 9, @palette.faint, "档位")
      @text.right(x + w - 90.0_f32, y + 53.0_f32, 9, @palette.faint, "价格")
      @text.right(x + w - 16.0_f32, y + 53.0_f32, 9, @palette.faint,
        "数量(手)")

      max_vol = 1_i64
      stock.asks.each { |l| max_vol = l.volume if l.volume > max_vol }
      stock.bids.each { |l| max_vol = l.volume if l.volume > max_vol }

      ask_names = ["卖五", "卖四", "卖三", "卖二", "卖一"]
      row_y = y + 66.0_f32
      5.times do |i|
        level = stock.asks[4 - i]
        book_row(x, row_y + i * 27.0_f32, w, ask_names[i], level.price,
          level.volume, @palette.down, max_vol)
      end

      mid_y = row_y + 5 * 27.0_f32
      @painter.rect(x + 8.0_f32, mid_y, w - 16.0_f32, 30.0_f32,
        @palette.panel_alt)
      @text.text(x + 16.0_f32, mid_y + 15.0_f32, 9, @palette.muted, "最新")
      @text.text(x + 56.0_f32, mid_y + 15.0_f32, 16,
        trend_color(stock.change), Fmt.price(stock.price))
      @text.right(x + w - 16.0_f32, mid_y + 15.0_f32, 10,
        trend_color(stock.change), Fmt.pct(stock.change_pct))

      bid_names = ["买一", "买二", "买三", "买四", "买五"]
      5.times do |i|
        level = stock.bids[i]
        book_row(x, mid_y + 30.0_f32 + i * 27.0_f32, w, bid_names[i],
          level.price, level.volume, @palette.up, max_vol)
      end

      footer_y = mid_y + 30.0_f32 + 5 * 27.0_f32
      @painter.hline(x + 12.0_f32, footer_y, w - 24.0_f32, @palette.grid)
      imbalance = stock.book_imbalance
      @text.text(x + 16.0_f32, footer_y + 18.0_f32, 9, @palette.muted,
        "委比")
      @text.text(x + 46.0_f32, footer_y + 18.0_f32, 10,
        trend_color(imbalance), Fmt.pct(imbalance))
      bid_ratio = (imbalance + 1.0) * 50.0
      @text.right(x + w - 16.0_f32, footer_y + 18.0_f32, 9,
        @palette.faint, "买盘 #{sprintf("%.0f", bid_ratio)}%")
    end

    private def book_row(x : Float32, y : Float32, w : Float32,
                         label : String, price : Float64, volume : Int64,
                         color : UInt32, max_vol : Int64) : Nil
      bar_w = (volume.to_f64 / max_vol.to_f64 * 132.0).to_f32
      @painter.rect(x + w - 16.0_f32 - bar_w, y + 6.0_f32, bar_w, 15.0_f32,
        Palette.alpha(color, 0x18_u8))
      @text.text(x + 16.0_f32, y + 13.5_f32, 10, @palette.muted, label)
      @text.right(x + w - 90.0_f32, y + 13.5_f32, 11, color,
        Fmt.price(price))
      @text.right(x + w - 16.0_f32, y + 13.5_f32, 10, @palette.muted,
        volume.to_s)
    end

    private def draw_info(stock : Stock) : Nil
      rect = @layout.info
      x = rect.origin.x
      y = rect.origin.y
      @text.text(x + 16.0_f32, y + 22.0_f32, 13, @palette.text, "行情数据")
      @painter.hline(x + 12.0_f32, y + 40.0_f32,
        rect.size.width - 24.0_f32, @palette.grid)

      items = [
        {"今开", Fmt.price(stock.open)},
        {"昨收", Fmt.price(stock.prev_close)},
        {"最高", Fmt.price(stock.high)},
        {"最低", Fmt.price(stock.low)},
        {"成交量", Fmt.volume(stock.volume)},
        {"成交额", Fmt.amount(stock.turnover)},
        {"换手率", Fmt.plain_pct(stock.turnover_rate)},
        {"振幅", Fmt.plain_pct(stock.amplitude)},
      ]
      col_x = [x + 16.0_f32, x + 154.0_f32]
      items.each_with_index do |item, i|
        cx = col_x[i % 2]
        cy = y + 62.0_f32 + (i // 2) * 38.0_f32
        @text.text(cx, cy - 9.0_f32, 9, @palette.muted, item[0])
        @text.text(cx, cy + 9.0_f32, 12, @palette.text, item[1])
      end

      sep_y = y + 194.0_f32
      @painter.hline(x + 12.0_f32, sep_y,
        rect.size.width - 24.0_f32, @palette.grid)
      rows = [
        {"市盈率", sprintf("%.1f", stock.pe)},
        {"总市值", Fmt.amount(stock.market_cap)},
        {"流通市值", Fmt.amount(stock.float_market_cap)},
        {"52周区间", "#{Fmt.price(stock.week52_low)} - #{Fmt.price(stock.week52_high)}"},
      ]
      rows.each_with_index do |row, i|
        cy = sep_y + 16.0_f32 + i * 19.0_f32
        @text.text(x + 16.0_f32, cy, 9, @palette.muted, row[0])
        @text.right(x + rect.size.width - 16.0_f32, cy, 10,
          @palette.text, row[1])
      end
    end

    private def draw_footer : Nil
      if @paused
        @text.text(20.0_f32, @layout.footer.origin.y + 14.0_f32, 9,
          @palette.amber, "行情已暂停 · SPACE 继续 · 模拟数据，不构成投资建议")
      else
        @text.text(20.0_f32, @layout.footer.origin.y + 14.0_f32, 9,
          @palette.muted,
          "模拟行情 · 每 #{@tick_interval_ms}ms 刷新 · 不构成投资建议")
      end
      @text.right(@layout.width.to_f32 - 20.0_f32,
        @layout.footer.origin.y + 14.0_f32, 9, @palette.muted,
        "↑↓ 选择   C 分时/日K   SPACE 暂停   T 主题   ESC 退出")
    end

    private def trend_color(change : Float64) : UInt32
      if change > 0.000001
        @palette.up
      elsif change < -0.000001
        @palette.down
      else
        @palette.muted
      end
    end

    private def map_y(value : Float64, low : Float64, high : Float64,
                      rect : Tessell::Rect) : Float32
      span = high - low
      return rect.max_y if span <= 0.0
      (rect.max_y - ((value - low) / span * rect.size.height).to_f32).to_f32
    end

    private def moving_average(candles : Array(Candle), period : Int32) : Float64
      return 0.0 if candles.size < period
      sum = 0.0
      i = candles.size - period
      while i < candles.size
        sum += candles[i].close
        i += 1
      end
      sum / period
    end
  end
end
