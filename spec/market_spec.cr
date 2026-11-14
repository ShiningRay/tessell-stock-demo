require "spec"
require "../src/stock_demo/market"

include StockDemo

describe StockDemo::Market do
  it "is deterministic for the same seed" do
    a = Market.new(seed: 7_u64)
    b = Market.new(seed: 7_u64)
    a.warmup(30)
    b.warmup(30)
    a.stocks.map(&.price).should eq(b.stocks.map(&.price))
    a.minute.should eq(b.minute)
    a.indices.map(&.value).should eq(b.indices.map(&.value))
  end

  it "produces the same seed-7 first price on every construction" do
    Market.new(seed: 7_u64).stocks.first.price.should eq(
      Market.new(seed: 7_u64).stocks.first.price)
  end

  it "keeps OHLC coherent while ticking" do
    market = Market.new(seed: 11_u64, start_minute: 130)
    40.times { market.tick }
    market.stocks.each do |s|
      s.high.should be >= s.price
      s.high.should be >= s.open
      s.low.should be <= s.price
      s.low.should be <= s.open
      s.high.should be >= s.low
      s.points.size.should be <= 240
      s.points.last.price.should eq(s.price)
    end
  end

  it "keeps prices inside the daily limit" do
    market = Market.new(seed: 19_u64, start_minute: 10)
    150.times { market.tick }
    market.stocks.each do |s|
      s.price.should be <= s.limit_up
      s.price.should be >= s.limit_down
    end
  end

  it "moves the market minute forward and appends at most one point per tick" do
    market = Market.new(seed: 23_u64, start_minute: 120)
    stock = market.stocks.first
    before = stock.points.size
    market.tick
    market.minute.should eq(121)
    stock.points.size.should eq(before + 1)
    stock.points.last.minute.should eq(121)
  end

  it "keeps a sorted five-level book around the last price" do
    market = Market.new(seed: 29_u64)
    stock = market.stocks.first
    stock.asks.size.should eq(5)
    stock.bids.size.should eq(5)
    stock.asks.each { |l| l.price.should be > stock.price }
    stock.bids.each { |l| l.price.should be < stock.price }
    4.times do |i|
      stock.asks[i].price.should be < stock.asks[i + 1].price
      stock.bids[i].price.should be > stock.bids[i + 1].price
    end
  end

  it "exposes change and amplitude against the previous close" do
    market = Market.new(seed: 31_u64)
    stock = market.stocks.first
    expected = (stock.price - stock.prev_close) / stock.prev_close
    stock.change_pct.should be_close(expected, 1e-12)
    stock.amplitude.should be_close(
      (stock.high - stock.low) / stock.prev_close, 1e-12)
  end

  it "counts advancing and declining stocks" do
    market = Market.new(seed: 37_u64)
    total = market.up_count + market.down_count + market.flat_count
    total.should eq(8)
  end
end

describe StockDemo::Fmt do
  it "formats prices, percentages and volumes" do
    Fmt.price(12.3).should eq("12.30")
    Fmt.signed_price(-1.2).should eq("-1.20")
    Fmt.pct(0.0123).should eq("+1.23%")
    Fmt.volume(1_500_000_i64).should eq("150.00万手")
    Fmt.time_label(0).should eq("09:30")
    Fmt.time_label(120).should eq("13:00")
    Fmt.time_label(239).should eq("14:59")
  end
end
