/*
 * Glass.ahk —— Windows 11 液态玻璃效果
 *
 * DWM Acrylic 只负责系统级的动态背景合成；不同 Windows 版本、显卡驱动和
 * 无边框窗口样式下，它可能退化成近似纯色的 tint。因此浮层还会在显示前
 * 采样一块真实桌面，把它降采样再放大形成局部模糊，并以很低的不透明度
 * 叠加几像素偏移的原图，模拟 Liquid Glass 的折射/位移。这样即使 DWM
 * Acrylic 不工作，用户仍然能看到真实背景，而不是一块深色面板。
 */

; 亚克力模糊。tint 为 AABBGGRR（注意不是 RGB，红蓝是反的）
GlassAcrylic(hwnd, tint := 0xB0141414) {
    static WCA_ACCENT_POLICY := 19
    static ACCENT_ENABLE_ACRYLICBLURBEHIND := 4

    ; ACCENT_POLICY { int AccentState; int AccentFlags; int GradientColor; int AnimationId; }
    accent := Buffer(16, 0)
    NumPut("int",  ACCENT_ENABLE_ACRYLICBLURBEHIND, accent,  0)
    NumPut("int",  2,    accent,  4)      ; AccentFlags: 绘制全部边缘
    NumPut("uint", tint, accent,  8)
    NumPut("int",  0,    accent, 12)

    ; WINCOMPATTRDATA { DWORD Attribute; PVOID pData; SIZE_T cbData; }  x64 下 24 字节
    data := Buffer(24, 0)
    NumPut("int",  WCA_ACCENT_POLICY, data,  0)
    NumPut("ptr",  accent.Ptr,        data,  8)
    NumPut("uptr", 16,                data, 16)

    return DllCall("user32\SetWindowCompositionAttribute", "ptr", hwnd, "ptr", data, "int")
}

; 圆角：0=系统默认 1=不圆角 2=大圆角 3=小圆角
GlassRounded(hwnd, pref := 2) {
    static DWMWA_WINDOW_CORNER_PREFERENCE := 33
    b := Buffer(4, 0)
    NumPut("int", pref, b)
    return DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                 , "uint", DWMWA_WINDOW_CORNER_PREFERENCE, "ptr", b, "uint", 4, "int")
}

; 边框颜色（0x00BBGGRR）。给玻璃加一圈高光，层次感来源
GlassBorder(hwnd, color := 0x00555555) {
    static DWMWA_BORDER_COLOR := 34
    b := Buffer(4, 0)
    NumPut("uint", color, b)
    return DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                 , "uint", DWMWA_BORDER_COLOR, "ptr", b, "uint", 4, "int")
}

; 一次性套用整套玻璃效果
GlassApply(hwnd, tint := 0xB0141414, border := 0x00555555) {
    GlassAcrylic(hwnd, tint)
    GlassRounded(hwnd, 2)
    GlassBorder(hwnd, border)
}

; 在浮层出现前采样屏幕区域，返回一个供 Picture 控件使用的 HBITMAP。
; x/y/w/h 均为物理像素；调用方负责按当前 DPI 计算它们。
GlassCaptureBackdrop(glX, glY, glW, glH) {
    if (glW <= 0 || glH <= 0)
        return 0

    static GLASS_SRCCOPY := 0x00CC0020
    static GLASS_CAPTUREBLT := 0x40000000
    static GLASS_HALFTONE := 4

    glScreenDc := DllCall("user32\GetDC", "ptr", 0, "ptr")
    if !glScreenDc
        return 0

    glSourceDc := 0
    glSourceBmp := 0
    glSourceOld := 0
    glSmallDc := 0
    glSmallBmp := 0
    glSmallOld := 0
    glFinalDc := 0
    glFinalBmp := 0
    glFinalOld := 0
    glTintDc := 0
    glTintBmp := 0
    glTintOld := 0
    glResult := 0

    try {
        ; 先把窗口背后的桌面拷贝到内存位图。
        glSourceDc := DllCall("gdi32\CreateCompatibleDC", "ptr", glScreenDc, "ptr")
        glSourceBmp := DllCall("gdi32\CreateCompatibleBitmap", "ptr", glScreenDc
                             , "int", glW, "int", glH, "ptr")
        if (!glSourceDc || !glSourceBmp)
            return 0
        glSourceOld := DllCall("gdi32\SelectObject", "ptr", glSourceDc
                             , "ptr", glSourceBmp, "ptr")
        if !DllCall("gdi32\BitBlt", "ptr", glSourceDc, "int", 0, "int", 0
                  , "int", glW, "int", glH, "ptr", glScreenDc
                  , "int", glX, "int", glY
                  , "uint", GLASS_SRCCOPY | GLASS_CAPTUREBLT, "int")
            return 0

        ; 降采样/放大是低成本的真实屏幕模糊，且不会依赖 DWM 的实现细节。
        glSmallW := Max(1, Floor(glW / 6))
        glSmallH := Max(1, Floor(glH / 6))
        glSmallDc := DllCall("gdi32\CreateCompatibleDC", "ptr", glScreenDc, "ptr")
        glSmallBmp := DllCall("gdi32\CreateCompatibleBitmap", "ptr", glScreenDc
                           , "int", glSmallW, "int", glSmallH, "ptr")
        if (!glSmallDc || !glSmallBmp)
            return 0
        glSmallOld := DllCall("gdi32\SelectObject", "ptr", glSmallDc
                            , "ptr", glSmallBmp, "ptr")
        DllCall("gdi32\SetStretchBltMode", "ptr", glSmallDc, "int", GLASS_HALFTONE)
        if !DllCall("gdi32\StretchBlt", "ptr", glSmallDc, "int", 0, "int", 0
                  , "int", glSmallW, "int", glSmallH, "ptr", glSourceDc
                  , "int", 0, "int", 0, "int", glW, "int", glH
                  , "uint", GLASS_SRCCOPY, "int")
            return 0

        glFinalDc := DllCall("gdi32\CreateCompatibleDC", "ptr", glScreenDc, "ptr")
        glFinalBmp := DllCall("gdi32\CreateCompatibleBitmap", "ptr", glScreenDc
                            , "int", glW, "int", glH, "ptr")
        if (!glFinalDc || !glFinalBmp)
            return 0
        glFinalOld := DllCall("gdi32\SelectObject", "ptr", glFinalDc
                            , "ptr", glFinalBmp, "ptr")
        DllCall("gdi32\SetStretchBltMode", "ptr", glFinalDc, "int", GLASS_HALFTONE)
        if !DllCall("gdi32\StretchBlt", "ptr", glFinalDc, "int", 0, "int", 0
                  , "int", glW, "int", glH, "ptr", glSmallDc
                  , "int", 0, "int", 0, "int", glSmallW, "int", glSmallH
                  , "uint", GLASS_SRCCOPY, "int")
            return 0

        ; 低 alpha 的错位原图提供可见的折射边缘。两个方向的偏移避免了
        ; 仅仅像一层普通锐化图，也让高对比桌面背景的变化能透出来。
        glBlend := 0x00280000 ; AC_SRC_OVER + SourceConstantAlpha 40
        DllCall("msimg32\AlphaBlend", "ptr", glFinalDc
              , "int", 3, "int", 2, "int", glW - 6, "int", glH - 4
              , "ptr", glSourceDc, "int", 0, "int", 0
              , "int", glW - 6, "int", glH - 4, "uint", glBlend, "int")
        DllCall("msimg32\AlphaBlend", "ptr", glFinalDc
              , "int", 0, "int", 0, "int", glW - 5, "int", glH - 5
              , "ptr", glSourceDc, "int", 5, "int", 5
              , "int", glW - 5, "int", glH - 5, "uint", 0x00160000, "int")

        ; DWM Acrylic 在部分机器上会成功返回但完全不改变像素，不能把
        ; 可读性寄托在系统合成层。用源图的五个点估计亮度，直接在最终
        ; 位图上叠加 tint：亮背景压暗，暗背景轻微提亮，中间亮度使用
        ; 蓝灰色半透明层。AlphaBlend 的 blend DWORD 是
        ; {BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat}。
        glLumaSum := 0.0
        glLumaSamples := 0
        for glProbe in [[Floor(glW / 4), Floor(glH / 4)]
                      , [Floor(glW / 2), Floor(glH / 4)]
                      , [Floor(glW * 3 / 4), Floor(glH / 2)]
                      , [Floor(glW / 3), Floor(glH * 3 / 4)]
                      , [Floor(glW * 2 / 3), Floor(glH * 3 / 4)]] {
            glPixel := DllCall("gdi32\GetPixel", "ptr", glSourceDc
                             , "int", glProbe[1], "int", glProbe[2], "uint")
            if (glPixel = 0xFFFFFFFF)
                continue
            glRed := glPixel & 0xFF
            glGreen := (glPixel >> 8) & 0xFF
            glBlue := (glPixel >> 16) & 0xFF
            glLumaSum += glRed * 0.2126 + glGreen * 0.7152 + glBlue * 0.0722
            glLumaSamples += 1
        }
        glLuma := glLumaSamples ? glLumaSum / glLumaSamples : 128

        ; 统一用暗色 tint，不再按背景明暗切换方向。
        ; 原因：面板上的文字全是浅色系（主标题 F0F2F4），要让它在任何背景上
        ; 都可读，面板就必须始终够暗。之前暗底分支往黑背景上叠冷白提亮，
        ; 方向正好相反 —— 实测纯黑背景下面板内平均亮度被抬到 224.9，
        ; 浅色文字直接糊没。
        ; 背景越亮压得越狠，保证对比度；同时保留约 1/3 的背景透过来维持玻璃感。
        glTintColor := 0x00241C14        ; COLORREF 是 BGR，对应 RGB 141C24
        glTintAlpha := (glLuma >= 150) ? 170 : 140

        ; 全尺寸纯色位图 + 1:1 混合。
        ; 原来的写法是把 1×1 位图拉伸到整块，AlphaBlend 在这种拉伸下会失败，
        ; 而返回值没人检查，于是染色静默地什么都没发生 ——
        ; 实测白底上面板亮度仍是 252，等于完全没染上。
        glTintDc := DllCall("gdi32\CreateCompatibleDC", "ptr", glScreenDc, "ptr")
        glTintBmp := DllCall("gdi32\CreateCompatibleBitmap", "ptr", glScreenDc
                           , "int", glW, "int", glH, "ptr")
        if (glTintDc && glTintBmp) {
            glTintOld := DllCall("gdi32\SelectObject", "ptr", glTintDc
                               , "ptr", glTintBmp, "ptr")
            GlassFillRect(glTintDc, 0, 0, glW, glH, glTintColor)
            glBlendOk := DllCall("msimg32\AlphaBlend", "ptr", glFinalDc
                  , "int", 0, "int", 0, "int", glW, "int", glH
                  , "ptr", glTintDc, "int", 0, "int", 0, "int", glW, "int", glH
                  , "uint", glTintAlpha << 16, "int")
            ; 兜底：混合真失败了就直接实心覆盖一层，宁可失去玻璃感也不能让字看不见
            if (!glBlendOk)
                GlassFillRect(glFinalDc, 0, 0, glW, glH, glTintColor)
        }

        ; 边缘高光直接写进最终 HBITMAP。Picture 控件只负责展示，不再
        ; 依赖 DWM border 或额外的 GUI 子控件来制造玻璃边缘。
        glEdgePx := Max(2, Floor(Min(glW, glH) / 220))
        GlassFillRect(glFinalDc, 1, 1, glW - 2, glEdgePx, 0x00FFF6EA)
        GlassFillRect(glFinalDc, 1, 1, glEdgePx, glH - 2, 0x00D9E8FF)
        GlassFillRect(glFinalDc, 1, glH - glEdgePx - 1, glW - 2, glEdgePx, 0x0030394A)
        GlassFillRect(glFinalDc, glW - glEdgePx - 1, 1, glEdgePx, glH - 2, 0x00202A3A)

        glResult := glFinalBmp
        glFinalBmp := 0 ; 所有权交给调用方/Gui Picture 的 HBITMAP 副本
        return glResult
    } finally {
        if (glSourceOld && glSourceDc)
            DllCall("gdi32\SelectObject", "ptr", glSourceDc, "ptr", glSourceOld, "ptr")
        if (glSmallOld && glSmallDc)
            DllCall("gdi32\SelectObject", "ptr", glSmallDc, "ptr", glSmallOld, "ptr")
        if (glFinalOld && glFinalDc)
            DllCall("gdi32\SelectObject", "ptr", glFinalDc, "ptr", glFinalOld, "ptr")
        if (glTintOld && glTintDc)
            DllCall("gdi32\SelectObject", "ptr", glTintDc, "ptr", glTintOld, "ptr")

        if (glSourceDc)
            DllCall("gdi32\DeleteDC", "ptr", glSourceDc)
        if (glSmallDc)
            DllCall("gdi32\DeleteDC", "ptr", glSmallDc)
        if (glFinalDc)
            DllCall("gdi32\DeleteDC", "ptr", glFinalDc)
        if (glTintDc)
            DllCall("gdi32\DeleteDC", "ptr", glTintDc)
        if (glSourceBmp)
            DllCall("gdi32\DeleteObject", "ptr", glSourceBmp)
        if (glSmallBmp)
            DllCall("gdi32\DeleteObject", "ptr", glSmallBmp)
        if (glFinalBmp)
            DllCall("gdi32\DeleteObject", "ptr", glFinalBmp)
        if (glTintBmp)
            DllCall("gdi32\DeleteObject", "ptr", glTintBmp)
        DllCall("user32\ReleaseDC", "ptr", 0, "ptr", glScreenDc)
    }
}

GlassFillRect(glDc, glX, glY, glW, glH, glColor) {
    if (glW <= 0 || glH <= 0)
        return 0
    glBrush := DllCall("gdi32\CreateSolidBrush", "uint", glColor, "ptr")
    if !glBrush
        return 0
    glRect := Buffer(16, 0)
    NumPut("int", glX, glRect, 0)
    NumPut("int", glY, glRect, 4)
    NumPut("int", glX + glW, glRect, 8)
    NumPut("int", glY + glH, glRect, 12)
    glOk := DllCall("user32\FillRect", "ptr", glDc, "ptr", glRect
                  , "ptr", glBrush, "int")
    DllCall("gdi32\DeleteObject", "ptr", glBrush)
    return glOk
}

; HBITMAP:* 会让 AHK 复制位图，原始句柄可立即安全释放。
GlassDeleteBitmap(glHBitmap) {
    if glHBitmap
        return DllCall("gdi32\DeleteObject", "ptr", glHBitmap, "int")
    return 1
}
