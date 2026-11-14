require "spec"
require "../src/stock_demo/layout"

include StockDemo

describe StockDemo::Layout do
  it "fits the three-column layout inside the content area" do
    l = Layout.new
    l.watchlist.max_x.should be < l.detail.origin.x
    l.detail.max_x.should be < l.book.origin.x
    l.book.max_y.should be < l.info.origin.y
    l.chart.max_y.should be <= l.footer.origin.y
    l.info.max_y.should be <= l.footer.origin.y
    l.watchlist.max_y.should be <= l.footer.origin.y
  end

  it "stacks the detail and chart cards with the standard gap" do
    l = Layout.new
    (l.chart.origin.y - l.detail.max_y).should eq(12.0_f32)
    (l.info.origin.y - l.book.max_y).should eq(12.0_f32)
  end

  it "maps each watch row to a non-overlapping hit rect inside the panel" do
    l = Layout.new
    Layout::WATCH_ROWS.times do |i|
      row = l.watch_row(i)
      row.origin.x.should be >= l.watchlist.origin.x
      row.max_x.should be <= l.watchlist.max_x
      row.max_y.should be <= l.watchlist.max_y
      l.watch_row_at(row.origin.y + row.size.height / 2).should eq(i)
    end
  end

  it "keeps both chart tabs inside the chart header" do
    l = Layout.new
    [l.tab_intraday, l.tab_daily].each do |tab|
      tab.origin.x.should be >= l.chart.origin.x
      tab.max_x.should be <= l.chart.max_x
      tab.max_y.should be <= l.chart.origin.y + 42.0_f32
    end
  end
end
