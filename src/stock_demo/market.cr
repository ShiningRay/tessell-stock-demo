# Deterministic simulated A-share market feed.
#
# No network access: every quote is generated locally from a seeded PRNG so
# that screenshots and specs are reproducible. The public surface is small
# enough to swap in a real feed adapter later (see README).
module StockDemo
  module Fmt
    extend self

    def price(value : Float64) : String
      sprintf("%.2f", value)
    end

    def signed_price(value : Float64) : String
      sprintf("%+.2f", value)
    end

    def pct(value : Float64) : String
      sprintf("%+.2f%%", value * 100.0)
    end

    def plain_pct(value : Float64) : String
      sprintf("%.2f%%", value * 100.0)
    end

    def volume(value : Int64) : String
      if value >= 100_000_000
        sprintf("%.2f亿手", value / 100_000_000.0)
      elsif value >= 10_000
        sprintf("%.2f万手", value / 10_000.0)
      else
        "#{value}手"
      end
    end

    def amount(value : Float64) : String
      if value >= 100_000_000
        sprintf("%.2f亿", value / 100_000_000.0)
      elsif value >= 10_000
        sprintf("%.2f万", value / 10_000.0)
      else
        sprintf("%.0f", value)
      end
    end

    # Market minute: 0..119 = 09:30..11:29, 120..239 = 13:00..14:59.
    def time_label(minute : Int32) : String
      m = minute.clamp(0, 239)
      total = m < 120 ? 9 * 60 + 30 + m : 13 * 60 + (m - 120)
      sprintf("%02d:%02d", total // 60, total % 60)
    end

    def clock(minute : Int32, second : Int32) : String
      m = minute.clamp(0, 239)
      total = m < 120 ? 9 * 60 + 30 + m : 13 * 60 + (m - 120)
      sprintf("%02d:%02d:%02d", total // 60, total % 60, second.clamp(0, 59))
    end

    def round2(value : Float64) : Float64
      (value * 100.0).round / 100.0
    end
  end

  struct Candle
    getter open : Float64
    getter high : Float64
    getter low : Float64
    getter close : Float64
    getter volume : Int64

    def initialize(@open : Float64, @high : Float64, @low : Float64,
                   @close : Float64, @volume : Int64)
    end
  end

  struct QuotePoint
    getter minute : Int32
    getter price : Float64
    getter avg : Float64
    getter volume : Int64

    def initialize(@minute : Int32, @price : Float64, @avg : Float64, @volume : Int64)
    end
  end

  struct BookLevel
    getter price : Float64
    getter volume : Int64

    def initialize(@price : Float64, @volume : Int64)
    end
  end

  # A single tradable instrument with 260 daily candles, a 240-minute intraday
  # series and a five-level order book. All mutations happen in #tick.
  class Stock
    getter code : String
    getter name : String
    getter market : String
    getter prev_close : Float64
    getter open : Float64
    getter high : Float64
    getter low : Float64
    getter price : Float64
    getter volume : Int64
    getter turnover : Float64
    getter points : Array(QuotePoint)
    getter candles : Array(Candle)
    getter asks : Array(BookLevel)
    getter bids : Array(BookLevel)
    getter limit_up : Float64
    getter limit_down : Float64
    getter pe : Float64
    getter total_shares : Float64
    getter float_shares : Float64
    getter week52_high : Float64
    getter week52_low : Float64

    @drift : Float64 = 0.0
    @prev_close : Float64 = 0.0
    @open : Float64 = 0.0
    @high : Float64 = 0.0
    @low : Float64 = 0.0
    @price : Float64 = 0.0
    @volume : Int64 = 0_i64
    @turnover : Float64 = 0.0

    def initialize(@code : String, @name : String, @market : String,
                   base_price : Float64, rng : Random, start_minute : Int32)
      @points = [] of QuotePoint
      @candles = [] of Candle
      @asks = [] of BookLevel
      @bids = [] of BookLevel
      @drift = rng.rand(-0.00006..0.00006)
      @pe = rng.rand(9.0..48.0)
      @total_shares = rng.rand(0.6e9..3.4e9)
      @float_shares = @total_shares * rng.rand(0.55..0.92)
      @limit_up = 0.0
      @limit_down = 0.0
      @week52_high = 0.0
      @week52_low = 0.0

      generate_history(base_price, rng)
      generate_intraday(start_minute, rng)
      rebuild_book(rng)
    end

    def change : Float64
      @price - @prev_close
    end

    def change_pct : Float64
      return 0.0 if @prev_close <= 0.0
      change / @prev_close
    end

    def amplitude : Float64
      return 0.0 if @prev_close <= 0.0
      (@high - @low) / @prev_close
    end

    def avg_price : Float64
      traded = @volume * 100.0
      return @price if traded <= 0.0
      @turnover / traded
    end

    def turnover_rate : Float64
      return 0.0 if @float_shares <= 0.0
      @volume * 100.0 / @float_shares
    end

    def market_cap : Float64
      @price * @total_shares
    end

    def float_market_cap : Float64
      @price * @float_shares
    end

    def book_imbalance : Float64
      bid = @bids.sum(&.volume)
      ask = @asks.sum(&.volume)
      total = bid + ask
      return 0.0 if total <= 0
      (bid - ask) / total
    end

    # Append one simulated minute. Called after Market advances its minute.
    def tick(rng : Random, minute : Int32) : Nil
      return if minute < 0 || minute > 239
      reversion = (@open - @price) / @open * 0.018
      ret = rng.rand(-0.0016..0.0016) + @drift + reversion
      next_price = Fmt.round2((@price * (1.0 + ret)).clamp(@limit_down, @limit_up))
      if next_price == @price
        step = rng.rand < 0.5 ? -0.01 : 0.01
        next_price = Fmt.round2((@price + step).clamp(@limit_down, @limit_up))
      end
      @price = next_price
      @high = @price if @price > @high
      @low = @price if @price < @low

      vol = (900 + rng.rand(5600)).to_i64
      vol *= 2 if minute < 12 || minute > 227
      @volume += vol
      @turnover += @price * vol * 100.0

      if @points.size > 0 && @points.last.minute == minute
        @points.pop
      end
      @points << QuotePoint.new(minute, @price, avg_price, vol)

      update_today_candle
      rebuild_book(rng)
    end

    # Roll to a new trading day: yesterday's close becomes the reference.
    def new_day(rng : Random) : Nil
      @prev_close = @price
      update_limits
      @open = Fmt.round2((@prev_close * (1.0 + rng.rand(-0.012..0.012))).clamp(@limit_down, @limit_up))
      @price = @open
      @high = @open
      @low = @open
      @volume = 0_i64
      @turnover = 0.0
      @points.clear
      vol = (1800 + rng.rand(4800)).to_i64
      @volume = vol
      @turnover = @price * vol * 100.0
      @points << QuotePoint.new(0, @price, avg_price, vol)
      @candles << Candle.new(@open, @high, @low, @price, @volume)
      @candles.shift if @candles.size > 300
      refresh_week52
      rebuild_book(rng)
    end

    private def generate_history(base_price : Float64, rng : Random) : Nil
      closes = Array(Float64).new(260)
      close = base_price * rng.rand(0.80..0.94)
      260.times do
        close *= 1.0 + rng.rand(-0.026..0.026) + 0.0007
        close = close.clamp(base_price * 0.35, base_price * 1.8)
        closes << close
      end
      scale = base_price / closes.last
      closes.map! { |c| c * scale }

      prev = closes.first * 0.998
      closes.each do |c|
        open = prev * (1.0 + rng.rand(-0.012..0.012))
        high = Math.max(open, c) * (1.0 + rng.rand(0.0005..0.014))
        low = Math.min(open, c) * (1.0 - rng.rand(0.0005..0.014))
        volume = (220_000 + rng.rand(1_400_000)).to_i64
        @candles << Candle.new(Fmt.round2(open), Fmt.round2(high),
          Fmt.round2(low), Fmt.round2(c), volume)
        prev = c
      end

      today = @candles.last
      @prev_close = @candles[-2].close
      @open = today.open
      @price = base_price
      @high = Math.max(today.high, @price)
      @low = Math.min(today.low, @price)
      @candles[-1] = Candle.new(today.open, @high, @low, @price, today.volume)
      update_limits
      refresh_week52
    end

    private def generate_intraday(start_minute : Int32, rng : Random) : Nil
      last = start_minute.clamp(0, 239)
      price = @open
      cum_vol = 0_i64
      cum_turnover = 0.0
      minute = 0
      while minute <= last
        if minute == 0
          price = @open
        else
          reversion = (@open - price) / @open * 0.05
          price = (price * (1.0 + rng.rand(-0.0022..0.0022) + reversion)).clamp(@limit_down, @limit_up)
          price = Fmt.round2(price)
        end
        vol = (900 + rng.rand(4600)).to_i64
        vol *= 2 if minute < 15 || minute > 225
        cum_vol += vol
        cum_turnover += price * vol * 100.0
        avg = cum_vol > 0 ? cum_turnover / (cum_vol * 100.0) : price
        @points << QuotePoint.new(minute, price, avg, vol)
        minute += 1
      end
      @price = @points.last.price
      @volume = cum_vol
      @turnover = cum_turnover
      @high = Math.max(@high, @points.max_of(&.price))
      @low = Math.min(@low, @points.min_of(&.price))
      update_today_candle
    end

    private def update_today_candle : Nil
      if @candles.size > 0
        today = @candles.last
        @candles[-1] = Candle.new(today.open, @high, @low, @price, @volume)
      end
    end

    private def update_limits : Nil
      ratio = @code.starts_with?("30") || @code.starts_with?("68") ? 0.20 : 0.10
      @limit_up = Fmt.round2(@prev_close * (1.0 + ratio))
      @limit_down = Fmt.round2(@prev_close * (1.0 - ratio))
    end

    private def refresh_week52 : Nil
      @week52_high = @candles.max_of(&.high)
      @week52_low = @candles.min_of(&.low)
    end

    private def rebuild_book(rng : Random) : Nil
      asks = Array(BookLevel).new(5)
      bids = Array(BookLevel).new(5)
      5.times do |i|
        ask_px = Fmt.round2(@price + 0.01 * (i + 1))
        bid_px = Fmt.round2(@price - 0.01 * (i + 1))
        ask_px = Fmt.round2(@limit_up) if ask_px > @limit_up
        bid_px = Fmt.round2(@limit_down) if bid_px < @limit_down
        asks << BookLevel.new(ask_px, (40 + rng.rand(2800)).to_i64)
        bids << BookLevel.new(bid_px, (40 + rng.rand(2800)).to_i64)
      end
      @asks = asks
      @bids = bids
    end
  end

  class IndexQuote
    getter code : String
    getter name : String
    getter prev_close : Float64
    getter value : Float64
    getter open : Float64
    getter high : Float64
    getter low : Float64

    def initialize(@code : String, @name : String, base : Float64, rng : Random)
      @prev_close = base * (1.0 + rng.rand(-0.008..0.008))
      @open = @prev_close * (1.0 + rng.rand(-0.006..0.006))
      @value = @open
      @high = Math.max(@open, @value)
      @low = Math.min(@open, @value)
    end

    def change : Float64
      @value - @prev_close
    end

    def change_pct : Float64
      return 0.0 if @prev_close <= 0.0
      change / @prev_close
    end

    def tick(rng : Random) : Nil
      ret = rng.rand(-0.0009..0.0009)
      @value *= 1.0 + ret
      @high = @value if @value > @high
      @low = @value if @value < @low
    end

    def new_day(rng : Random) : Nil
      @prev_close = @value
      @open = @prev_close * (1.0 + rng.rand(-0.006..0.006))
      @value = @open
      @high = @open
      @low = @open
    end
  end

  class Market
    getter stocks : Array(Stock)
    getter indices : Array(IndexQuote)
    getter minute : Int32
    getter day : Int32
    getter tick_count : Int32
    getter seed : UInt64

    SEED_STOCKS = [
      {"600519", "贵州茅台", "沪A", 1682.40},
      {"000001", "平安银行", "深A", 11.58},
      {"300750", "宁德时代", "深A", 246.30},
      {"601318", "中国平安", "沪A", 52.86},
      {"000858", "五粮液", "深A", 138.70},
      {"002594", "比亚迪", "深A", 258.40},
      {"688981", "中芯国际", "沪A", 89.35},
      {"600036", "招商银行", "沪A", 38.92},
    ]

    def initialize(seed : UInt64 = 20_261_114_u64, start_minute : Int32 = 150)
      @seed = seed
      @rng = Random.new(seed)
      @minute = start_minute.clamp(0, 239)
      @day = 1
      @tick_count = 0
      @stocks = Array(Stock).new(SEED_STOCKS.size)
      SEED_STOCKS.each do |row|
        @stocks << Stock.new(row[0], row[1], row[2], row[3],
          @rng, @minute)
      end
      @indices = [
        IndexQuote.new("000001", "上证指数", 3_286.0, @rng),
        IndexQuote.new("399001", "深证成指", 10_482.0, @rng),
        IndexQuote.new("399006", "创业板指", 2_168.0, @rng),
        IndexQuote.new("000688", "科创50", 1_182.0, @rng),
        IndexQuote.new("899050", "北证50", 1_420.0, @rng),
      ]
    end

    def tick : Nil
      @tick_count += 1
      if @minute >= 239
        @minute = 0
        @day += 1
        @stocks.each(&.new_day(@rng))
        @indices.each(&.new_day(@rng))
      else
        @minute += 1
        @stocks.each { |stock| stock.tick(@rng, @minute) }
        @indices.each(&.tick(@rng))
      end
    end

    def warmup(ticks : Int32) : Nil
      ticks.clamp(0, 10_000).times { tick }
    end

    def up_count : Int32
      @stocks.count { |s| s.change > 0.0001 }
    end

    def down_count : Int32
      @stocks.count { |s| s.change < -0.0001 }
    end

    def flat_count : Int32
      @stocks.size - up_count - down_count
    end

    def clock_second : Int32
      (@tick_count * 7) % 60
    end
  end
end
