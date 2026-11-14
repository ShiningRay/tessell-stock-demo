module StockDemo
  # RGBA 0xRRGGBBAA palette. Chinese market convention: red = up, green = down.
  class Palette
    getter bg : UInt32
    getter panel : UInt32
    getter panel_alt : UInt32
    getter card : UInt32
    getter border : UInt32
    getter text : UInt32
    getter muted : UInt32
    getter faint : UInt32
    getter accent : UInt32
    getter accent_soft : UInt32
    getter up : UInt32
    getter up_soft : UInt32
    getter down : UInt32
    getter down_soft : UInt32
    getter grid : UInt32
    getter amber : UInt32
    getter purple : UInt32

    def initialize(@bg, @panel, @panel_alt, @card, @border, @text, @muted,
                   @faint, @accent, @accent_soft, @up, @up_soft, @down,
                   @down_soft, @grid, @amber, @purple : UInt32)
    end

    def self.dark : Palette
      new(
        bg: 0x0b0f16ff_u32,
        panel: 0x121822ff_u32,
        panel_alt: 0x18202cff_u32,
        card: 0x161e2aff_u32,
        border: 0x232d3cff_u32,
        text: 0xe8edf7ff_u32,
        muted: 0x8290a6ff_u32,
        faint: 0x5a667aff_u32,
        accent: 0x4c8dffff_u32,
        accent_soft: 0x1d3050ff_u32,
        up: 0xff5d62ff_u32,
        up_soft: 0x3a1a20ff_u32,
        down: 0x23c26aff_u32,
        down_soft: 0x12301fff_u32,
        grid: 0x1e2736ff_u32,
        amber: 0xf2b84bff_u32,
        purple: 0xb18cffff_u32,
      )
    end

    def self.light : Palette
      new(
        bg: 0xeef2f8ff_u32,
        panel: 0xffffffff_u32,
        panel_alt: 0xf6f8fcff_u32,
        card: 0xfafbfdff_u32,
        border: 0xdce3eeff_u32,
        text: 0x18202eff_u32,
        muted: 0x66738aff_u32,
        faint: 0x95a0b4ff_u32,
        accent: 0x2f6fedff_u32,
        accent_soft: 0xe4edffff_u32,
        up: 0xe5484dff_u32,
        up_soft: 0xfdebecff_u32,
        down: 0x159a55ff_u32,
        down_soft: 0xe7f7eeff_u32,
        grid: 0xe6ebf3ff_u32,
        amber: 0xc98a12ff_u32,
        purple: 0x7c5ce6ff_u32,
      )
    end

    # Replace the alpha byte of an RGBA color.
    def self.alpha(color : UInt32, alpha : UInt8) : UInt32
      (color & 0xffffff00_u32) | alpha.to_u32
    end
  end
end
