require "tessell"
require "./app"

@[Link("kernel32")]
lib DemoKernel32
  fun GetModuleHandleW(lpModuleName : UInt16*) : Void*
  fun GetLastError : UInt32
end

@[Link("user32")]
lib DemoUser32
  struct WNDCLASSEXW
    cbSize : UInt32
    style : UInt32
    lpfnWndProc : (Void*, UInt32, UInt64, Int64 -> Int64)
    cbClsExtra : Int32
    cbWndExtra : Int32
    hInstance : Void*
    hIcon : Void*
    hCursor : Void*
    hbrBackground : Void*
    lpszMenuName : UInt16*
    lpszClassName : UInt16*
    hIconSm : Void*
  end

  struct POINT
    x : Int32
    y : Int32
  end

  struct MSG
    hwnd : Void*
    message : UInt32
    wParam : UInt64
    lParam : Int64
    time : UInt32
    pt : POINT
  end

  struct RECT
    left : Int32
    top : Int32
    right : Int32
    bottom : Int32
  end

  fun RegisterClassExW(lpWndClass : WNDCLASSEXW*) : UInt16
  fun CreateWindowExW(dwExStyle : UInt32, lpClassName : UInt16*, lpWindowName : UInt16*,
                      dwStyle : UInt32, x : Int32, y : Int32, nWidth : Int32, nHeight : Int32,
                      hWndParent : Void*, hMenu : Void*, hInstance : Void*, lpParam : Void*) : Void*
  fun ShowWindow(hWnd : Void*, nCmdShow : Int32) : Int32
  fun UpdateWindow(hWnd : Void*) : Int32
  fun DestroyWindow(hWnd : Void*) : Int32
  fun PostQuitMessage(nExitCode : Int32) : Void
  fun DefWindowProcW(hWnd : Void*, msg : UInt32, wParam : UInt64, lParam : Int64) : Int64
  fun PeekMessageW(lpMsg : MSG*, hWnd : Void*, wMsgFilterMin : UInt32, wMsgFilterMax : UInt32, wRemoveMsg : UInt32) : Int32
  fun TranslateMessage(lpMsg : MSG*) : Int32
  fun DispatchMessageW(lpMsg : MSG*) : Int64
  fun GetDC(hWnd : Void*) : Void*
  fun ReleaseDC(hWnd : Void*, hDC : Void*) : Int32
  fun LoadCursorW(hInstance : Void*, lpCursorName : UInt16*) : Void*
  fun AdjustWindowRectEx(lpRect : RECT*, dwStyle : UInt32, bMenu : Int32, dwExStyle : UInt32) : Int32
end

@[Link("gdi32")]
lib DemoGdi32
  struct PIXELFORMATDESCRIPTOR
    nSize : UInt16
    nVersion : UInt16
    dwFlags : UInt32
    iPixelType : UInt8
    cColorBits : UInt8
    cRedBits : UInt8
    cRedShift : UInt8
    cGreenBits : UInt8
    cGreenShift : UInt8
    cBlueBits : UInt8
    cBlueShift : UInt8
    cAlphaBits : UInt8
    cAlphaShift : UInt8
    cAccumBits : UInt8
    cAccumRedBits : UInt8
    cAccumGreenBits : UInt8
    cAccumBlueBits : UInt8
    cAccumAlphaBits : UInt8
    cDepthBits : UInt8
    cStencilBits : UInt8
    cAuxBuffers : UInt8
    iLayerType : UInt8
    bReserved : UInt8
    dwLayerMask : UInt32
    dwVisibleMask : UInt32
    dwDamageMask : UInt32
  end

  fun ChoosePixelFormat(hdc : Void*, ppfd : PIXELFORMATDESCRIPTOR*) : Int32
  fun SetPixelFormat(hdc : Void*, format : Int32, ppfd : PIXELFORMATDESCRIPTOR*) : Int32
  fun SwapBuffers(hdc : Void*) : Int32
end

@[Link("opengl32")]
lib DemoWGL
  fun wglCreateContext(hdc : Void*) : Void*
  fun wglMakeCurrent(hdc : Void*, hglrc : Void*) : Int32
  fun wglDeleteContext(hglrc : Void*) : Int32
end

module StockDemo
  module Native
    class_property quit_requested : Bool = false
    class_property click_pending : Bool = false
    class_property move_pending : Bool = false
    class_property mouse_x : Int32 = 0
    class_property mouse_y : Int32 = 0
    class_property keys : Array(UInt32) = [] of UInt32
    class_property app : App? = nil
  end

  WS_OVERLAPPEDWINDOW = 0x00cf0000_u32
  WS_THICKFRAME       = 0x00040000_u32
  WS_MAXIMIZEBOX      = 0x00010000_u32
  WS_VISIBLE          = 0x10000000_u32
  CW_USEDEFAULT       = 0x80000000_u32.to_i32!
  SW_SHOW             =          5
  PM_REMOVE           = 0x0001_u32
  WM_CLOSE            = 0x0010_u32
  WM_DESTROY          = 0x0002_u32
  WM_QUIT             = 0x0012_u32
  WM_ERASEBKGND       = 0x0014_u32
  WM_KEYDOWN          = 0x0100_u32
  WM_MOUSEMOVE        = 0x0200_u32
  WM_LBUTTONDOWN      = 0x0201_u32
  IDC_ARROW           = Pointer(UInt16).new(32512_u64)
  CS_OWNDC            = 0x0020_u32

  PFD_DRAW_TO_WINDOW = 0x00000004_u32
  PFD_SUPPORT_OPENGL = 0x00000020_u32
  PFD_DOUBLEBUFFER   = 0x00000001_u32
  PFD_TYPE_RGBA      =           0_u8
  PFD_MAIN_PLANE     =           0_u8

  DEMO_WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
    case msg
    when WM_CLOSE
      DemoUser32.DestroyWindow(hwnd)
      return 0_i64
    when WM_DESTROY
      DemoUser32.PostQuitMessage(0)
      Native.quit_requested = true
      return 0_i64
    when WM_ERASEBKGND
      return 1_i64
    when WM_KEYDOWN
      Native.keys << (wparam & 0xffff_u64).to_u32
    when WM_MOUSEMOVE
      x = (lparam & 0xffff_u64).to_i32
      x -= 65_536 if x > 32_767
      y = ((lparam >> 16) & 0xffff_u64).to_i32
      y -= 65_536 if y > 32_767
      Native.mouse_x = x
      Native.mouse_y = y
      Native.move_pending = true
    when WM_LBUTTONDOWN
      x = (lparam & 0xffff_u64).to_i32
      x -= 65_536 if x > 32_767
      y = ((lparam >> 16) & 0xffff_u64).to_i32
      y -= 65_536 if y > 32_767
      Native.mouse_x = x
      Native.mouse_y = y
      Native.click_pending = true
    end
    DemoUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
  end

  def self.to_wstr(string : String) : Slice(UInt16)
    utf16 = string.to_utf16
    buffer = Slice(UInt16).new(utf16.size + 1, 0_u16)
    utf16.size.times { |i| buffer[i] = utf16[i] }
    buffer
  end

  def self.fail(message : String) : NoReturn
    error = DemoKernel32.GetLastError
    STDERR.puts "error=#{message} win32_error=#{error}"
    exit 1
  end

  # Win32 window + WGL context. The message loop stays on the creating thread.
  class Window
    getter hwnd : Void*
    getter hdc : Void*
    getter hglrc : Void*

    def initialize(title : String, width : Int32, height : Int32)
      hinstance = DemoKernel32.GetModuleHandleW(Pointer(UInt16).null)
      StockDemo.fail("GetModuleHandleW") if hinstance.null?

      class_name = StockDemo.to_wstr("TessellStockDemo")
      window_title = StockDemo.to_wstr(title)

      wc = DemoUser32::WNDCLASSEXW.new
      wc.cbSize = sizeof(DemoUser32::WNDCLASSEXW).to_u32
      wc.style = CS_OWNDC
      wc.lpfnWndProc = DEMO_WNDPROC
      wc.hInstance = hinstance
      wc.hCursor = DemoUser32.LoadCursorW(Pointer(Void).null, IDC_ARROW)
      wc.lpszClassName = class_name.to_unsafe
      atom = DemoUser32.RegisterClassExW(pointerof(wc))
      StockDemo.fail("RegisterClassExW") if atom == 0

      style = WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX
      rect = DemoUser32::RECT.new
      rect.left = 0
      rect.top = 0
      rect.right = width
      rect.bottom = height
      DemoUser32.AdjustWindowRectEx(pointerof(rect), style, 0, 0)
      win_w = rect.right - rect.left
      win_h = rect.bottom - rect.top

      @hwnd = DemoUser32.CreateWindowExW(0_u32, class_name.to_unsafe,
        window_title.to_unsafe, style | WS_VISIBLE, CW_USEDEFAULT,
        CW_USEDEFAULT, win_w, win_h, Pointer(Void).null, Pointer(Void).null,
        hinstance, Pointer(Void).null)
      StockDemo.fail("CreateWindowExW") if @hwnd.null?
      DemoUser32.ShowWindow(@hwnd, SW_SHOW)
      DemoUser32.UpdateWindow(@hwnd)

      @hdc = DemoUser32.GetDC(@hwnd)
      StockDemo.fail("GetDC") if @hdc.null?

      pfd = DemoGdi32::PIXELFORMATDESCRIPTOR.new
      pfd.nSize = sizeof(DemoGdi32::PIXELFORMATDESCRIPTOR).to_u16
      pfd.nVersion = 1_u16
      pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
      pfd.iPixelType = PFD_TYPE_RGBA
      pfd.cColorBits = 32_u8
      pfd.cDepthBits = 24_u8
      pfd.cStencilBits = 8_u8
      pfd.iLayerType = PFD_MAIN_PLANE
      format = DemoGdi32.ChoosePixelFormat(@hdc, pointerof(pfd))
      StockDemo.fail("ChoosePixelFormat") if format == 0
      if DemoGdi32.SetPixelFormat(@hdc, format, pointerof(pfd)) == 0
        StockDemo.fail("SetPixelFormat")
      end

      @hglrc = DemoWGL.wglCreateContext(@hdc)
      StockDemo.fail("wglCreateContext") if @hglrc.null?
      if DemoWGL.wglMakeCurrent(@hdc, @hglrc) == 0
        StockDemo.fail("wglMakeCurrent")
      end
    end

    def pump_messages : Nil
      msg = DemoUser32::MSG.new
      while DemoUser32.PeekMessageW(pointerof(msg), Pointer(Void).null,
              0_u32, 0_u32, PM_REMOVE) != 0
        if msg.message == WM_QUIT
          Native.quit_requested = true
          break
        end
        DemoUser32.TranslateMessage(pointerof(msg))
        DemoUser32.DispatchMessageW(pointerof(msg))
      end
    end

    def swap_buffers : Nil
      DemoGdi32.SwapBuffers(@hdc)
    end

    def close : Nil
      DemoWGL.wglMakeCurrent(Pointer(Void).null, Pointer(Void).null)
      DemoWGL.wglDeleteContext(@hglrc)
      DemoUser32.ReleaseDC(@hwnd, @hdc)
      DemoUser32.DestroyWindow(@hwnd) unless Native.quit_requested
      Native.quit_requested = true
    end
  end
end
