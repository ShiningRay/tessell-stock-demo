require "tessell"
require "tessell/render/gl/gl_backend"
require "./stock_demo/win32"

USAGE = <<-TEXT
Tessell 行情终端（模拟 A 股）

用法:
  tessell-stock-demo [options]

选项:
  --theme=dark|light   启动主题（默认 dark）
  --tick-ms=N          模拟行情刷新间隔，毫秒（默认 500）
  --warmup=N           启动前预演 N 个 tick（默认 0）
  --seed=N             模拟随机种子（默认 20261114）
  --font=PATH          字体文件（默认 C:/Windows/Fonts/msyh.ttc）
  --frames=N           只渲染 N 帧后退出（用于截图/自动化）
  --screenshot=PATH    退出前保存 TSRAW 截图
  --view=intraday|daily 启动图表视图（默认 intraday）
  --select=N           启动时选中第 N 只自选股（0 起）
  --fps=N              交互帧率上限（默认 60）
  --help               显示本帮助

快捷键:
  ↑ / ↓     切换自选股     1-8      直接选择
  C / K     分时 / 日K     SPACE    暂停 / 继续
  T         深色 / 浅色     ESC      退出

数据为本地模拟生成，仅用于框架与交互演示，不构成投资建议。
TEXT

frames = 0
screenshot = ""
dark = true
tick_ms = 500
warmup = 0
seed = 20_261_114_u64
font_path = "C:/Windows/Fonts/msyh.ttc"
fps = 60
view_daily = false
select_index = 0

show_help = false
ARGV.each do |arg|
  case arg
  when "--help", "-h"
    show_help = true
  when .starts_with?("--theme=")
    dark = arg.split("=", 2)[1] != "light"
  when .starts_with?("--tick-ms=")
    tick_ms = arg.split("=", 2)[1].to_i
  when .starts_with?("--warmup=")
    warmup = arg.split("=", 2)[1].to_i
  when .starts_with?("--seed=")
    seed = arg.split("=", 2)[1].to_u64
  when .starts_with?("--font=")
    font_path = arg.split("=", 2)[1]
  when .starts_with?("--frames=")
    frames = arg.split("=", 2)[1].to_i
  when .starts_with?("--screenshot=")
    screenshot = arg.split("=", 2)[1]
  when .starts_with?("--fps=")
    fps = arg.split("=", 2)[1].to_i
  when .starts_with?("--view=")
    view_daily = arg.split("=", 2)[1] == "daily"
  when .starts_with?("--select=")
    select_index = arg.split("=", 2)[1].to_i
  end
end

if show_help
  puts USAGE
  exit 0
end

fps = fps.clamp(1, 240)

def apply_pending_input(app : StockDemo::App) : Nil
  if StockDemo::Native.click_pending
    StockDemo::Native.click_pending = false
    app.handle_pointer_down(StockDemo::Native.mouse_x.to_f32,
      StockDemo::Native.mouse_y.to_f32)
  end
  if StockDemo::Native.move_pending
    StockDemo::Native.move_pending = false
    app.handle_pointer_move(StockDemo::Native.mouse_x.to_f32,
      StockDemo::Native.mouse_y.to_f32)
  end
  unless StockDemo::Native.keys.empty?
    StockDemo::Native.keys.each { |vk| app.handle_vk(vk) }
    StockDemo::Native.keys.clear
  end
end

result = Channel(Tuple(Int32, String)).new

Fiber::ExecutionContext::Isolated.new("tessell-stock-demo") do
  begin
    unless Tessell::Text::FtMeasurer.available?
      reason = Tessell::Text::FtMeasurer.unavailable_reason
      result.send({1, "error=ft_unavailable reason=#{reason.inspect}"})
      next
    end

    window = StockDemo::Window.new("Tessell 行情终端（模拟）",
      1280, 800)
    app = StockDemo::App.new(seed: seed, warmup: warmup, dark: dark,
      tick_ms: tick_ms, font_path: font_path)
    app.select_stock(select_index)
    app.view = view_daily ? StockDemo::View::Daily : StockDemo::View::Intraday
    StockDemo::Native.app = app
    StockDemo::Native.quit_requested = false

    frame_interval = 1000.0 / fps.to_f64
    virtual_now = 0.0
    start_instant = Time.instant
    rendered = 0

    if frames > 0
      frames.times do |i|
        break if StockDemo::Native.quit_requested || app.quit_requested?
        window.pump_messages
        apply_pending_input(app)
        app.run_frame(virtual_now + (i + 1) * frame_interval)
        window.swap_buffers
        rendered += 1
      end
    else
      until StockDemo::Native.quit_requested || app.quit_requested?
        window.pump_messages
        apply_pending_input(app)
        app.run_frame(start_instant.elapsed.total_milliseconds.to_f64)
        window.swap_buffers
        rendered += 1
        sleep 16.milliseconds
      end
    end

    unless screenshot.empty?
      app.capture(screenshot)
    end

    stats = app.stats_line
    StockDemo::Native.app = nil
    app.dispose
    window.close
    result.send({0, "#{stats} rendered=#{rendered} screenshot=#{screenshot}"})
  rescue ex
    backtrace = ex.backtrace?.try(&.first(6).join(" | ")) || ""
    result.send({1, "error=exception message=#{ex.message.inspect} " \
                    "backtrace=#{backtrace.inspect}"})
  end
end

status, line = result.receive
puts line
exit status
