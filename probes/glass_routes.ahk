#Requires AutoHotkey v2.0
#SingleInstance Force

; Independent probe. Run in an interactive desktop session. Results are written
; beside this script; no keyboard mapping or action code is loaded.
DllCall("user32\SetProcessDPIAware", "int")
resultPath := A_ScriptDir "\glass_routes-results.txt"
outFile := FileOpen(resultPath, "w", "UTF-8")
outFile.WriteLine("AHK=" A_AhkVersion " DPI=" A_ScreenDPI " screen=" A_ScreenWidth "x" A_ScreenHeight)

ProbeAccent(outFile)
ProbePicture(outFile)
outFile.Close()
ExitApp()

ProbeAccent(outFile) {
    targetX := Round((A_ScreenWidth - 1000) / 2)
    targetY := Round((A_ScreenHeight - 480) / 2)
    panelX := targetX + 200
    panelY := targetY + 80
    target := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
    target.BackColor := "FF00FF"
    stripeX := 40
    while (stripeX < 1000) {
        target.Add("Progress", Format("x{} y0 w40 h480 BackgroundFFFFFF cFFFFFF", stripeX), 0)
        stripeX += 80
    }
    target.Show(Format("NoActivate x{} y{} w1000 h480", targetX, targetY))
    Sleep(350)

    outsideMagenta := ProbeScreenPixel(targetX + 20, targetY + 240)
    outsideWhite := ProbeScreenPixel(targetX + 60, targetY + 240)
    outFile.WriteLine("TARGET_OUTSIDE magenta=" ProbeRgb(outsideMagenta)
        " white=" ProbeRgb(outsideWhite))
    targetOk := (outsideMagenta != 0xFFFFFFFF && outsideWhite != 0xFFFFFFFF
        && (outsideMagenta & 0xFF) >= 245
        && ((outsideMagenta >> 8) & 0xFF) <= 10
        && ((outsideMagenta >> 16) & 0xFF) >= 245
        && (outsideWhite & 0xFF) >= 245
        && ((outsideWhite >> 8) & 0xFF) >= 245
        && ((outsideWhite >> 16) & 0xFF) >= 245)
    outFile.WriteLine("TARGET_SELF_CHECK=" (targetOk ? "PASS" : "FAIL"))

    if targetOk {
        for route in [{name: "key_no_accent", state: 0, key: true}
                    , {name: "lime_blur3", state: 3, key: false}
                    , {name: "key_blur3", state: 3, key: true}
                    , {name: "blur3_then_key", state: 3, key: true, accentFirst: true}
                    , {name: "key_host5", state: 5, key: true}
                    , {name: "host5_then_key", state: 5, key: true, accentFirst: true}] {
            panel := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
            panel.BackColor := "00FF00"
            panel.Show(Format("NoActivate x{} y{} w600 h320", panelX, panelY))
            accentRet := -1
            if (route.HasOwnProp("accentFirst") && route.accentFirst) {
                accentRet := ProbeSetAccent(panel.Hwnd, route.state)
                WinSetTransColor("00FF00", panel.Hwnd)
            } else {
                if route.key
                    WinSetTransColor("00FF00", panel.Hwnd)
                if route.state
                    accentRet := ProbeSetAccent(panel.Hwnd, route.state)
            }
            WinRedraw(panel.Hwnd)
            Sleep(500)
            colors := []
            for sampleX in [20, 60, 100, 140, 180, 220, 260, 300]
                colors.Push(ProbeScreenPixel(panelX + sampleX, panelY + 160))
            outFile.WriteLine(route.name " accent_ret=" accentRet
                " stripe_delta=" Round(ProbeStripeDelta(colors), 1)
                " pixels=" ProbePixels(colors))
            panel.Destroy()
            Sleep(150)
        }
    }
    target.Destroy()
}

ProbePicture(outFile) {
    dc := DllCall("user32\GetDC", "ptr", 0, "ptr")
    memDc := DllCall("gdi32\CreateCompatibleDC", "ptr", dc, "ptr")
    ddb := DllCall("gdi32\CreateCompatibleBitmap", "ptr", dc
        , "int", 160, "int", 120, "ptr")
    old := DllCall("gdi32\SelectObject", "ptr", memDc, "ptr", ddb, "ptr")
    brush := DllCall("gdi32\CreateSolidBrush", "uint", 0x00FF0000, "ptr")
    rect := Buffer(16, 0)
    NumPut("int", 160, rect, 8)
    NumPut("int", 120, rect, 12)
    DllCall("user32\FillRect", "ptr", memDc, "ptr", rect, "ptr", brush)
    DllCall("gdi32\DeleteObject", "ptr", brush)
    outFile.WriteLine("DDB getpixel=" ProbeRgb(DllCall("gdi32\GetPixel"
        , "ptr", memDc, "int", 80, "int", 60, "uint")))
    DllCall("gdi32\SelectObject", "ptr", memDc, "ptr", old)
    DllCall("gdi32\DeleteDC", "ptr", memDc)
    DllCall("user32\ReleaseDC", "ptr", 0, "ptr", dc)

    info := Buffer(40, 0)
    NumPut("uint", 40, info, 0)
    NumPut("int", 160, info, 4)
    NumPut("int", -120, info, 8)
    NumPut("ushort", 1, info, 12)
    NumPut("ushort", 32, info, 14)
    bits := 0
    dib := DllCall("gdi32\CreateDIBSection", "ptr", 0, "ptr", info
        , "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    if dib && bits {
        pixelIndex := 0
        while (pixelIndex < 160 * 120) {
            NumPut("uint", 0xFF00FFFF, bits + pixelIndex * 4)
            pixelIndex += 1
        }
    }
    outFile.WriteLine("BITMAP_HANDLES ddb=" ddb " dib=" dib " dib_bits=" bits)
    if !(ddb && dib && bits) {
        if ddb
            DllCall("gdi32\DeleteObject", "ptr", ddb)
        if dib
            DllCall("gdi32\DeleteObject", "ptr", dib)
        return
    }

    picX := Round((A_ScreenWidth - 380) / 2)
    picY := Round((A_ScreenHeight - 160) / 2)
    guiPic := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
    guiPic.BackColor := "FF0000"
    picDdb := guiPic.Add("Picture", "x20 y20 w160 h120", "HBITMAP:*" ddb)
    picDib := guiPic.Add("Picture", "x200 y20 w160 h120", "HBITMAP:*" dib)
    outFile.WriteLine("STM_GETIMAGE ddb=" DllCall("user32\SendMessageW", "ptr", picDdb.Hwnd
        , "uint", 0x173, "uptr", 0, "ptr", 0, "ptr")
        " dib=" DllCall("user32\SendMessageW", "ptr", picDib.Hwnd
        , "uint", 0x173, "uptr", 0, "ptr", 0, "ptr"))
    DllCall("gdi32\DeleteObject", "ptr", ddb)
    DllCall("gdi32\DeleteObject", "ptr", dib)
    guiPic.Show(Format("NoActivate x{} y{} w380 h160", picX, picY))
    Sleep(500)
    backgroundPixel := ProbeScreenPixel(picX + 10, picY + 80)
    pictureTargetOk := (backgroundPixel != 0xFFFFFFFF
        && (backgroundPixel & 0xFF) >= 245
        && ((backgroundPixel >> 8) & 0xFF) <= 10
        && ((backgroundPixel >> 16) & 0xFF) <= 10)
    outFile.WriteLine("PICTURE_BACKGROUND=" ProbeRgb(backgroundPixel)
        " PICTURE_TARGET_SELF_CHECK=" (pictureTargetOk ? "PASS" : "FAIL"))
    if pictureTargetOk
        outFile.WriteLine("PICTURE DDB=" ProbeRgb(ProbeScreenPixel(picX + 100, picY + 80))
            " DIB=" ProbeRgb(ProbeScreenPixel(picX + 280, picY + 80)))
    guiPic.Destroy()
}

ProbeSetAccent(hwnd, accentState) {
    accent := Buffer(16, 0)
    NumPut("int", accentState, accent, 0)
    NumPut("int", 2, accent, 4)
    NumPut("uint", 0xB0141414, accent, 8)
    data := Buffer(24, 0)
    NumPut("int", 19, data, 0)
    NumPut("ptr", accent.Ptr, data, 8)
    NumPut("uptr", 16, data, 16)
    return DllCall("user32\SetWindowCompositionAttribute"
        , "ptr", hwnd, "ptr", data, "int")
}

ProbeScreenPixel(x, y) {
    dc := DllCall("user32\GetDC", "ptr", 0, "ptr")
    if !dc
        return 0xFFFFFFFF
    value := DllCall("gdi32\GetPixel", "ptr", dc, "int", x, "int", y, "uint")
    DllCall("user32\ReleaseDC", "ptr", 0, "ptr", dc)
    return value
}

ProbeRgb(color) {
    if (color = 0xFFFFFFFF)
        return "INVALID"
    return Format("{},{},{}", color & 0xFF, (color >> 8) & 0xFF
        , (color >> 16) & 0xFF)
}

ProbeStripeDelta(colors) {
    total := 0
    pairs := 0
    index := 1
    while (index < colors.Length) {
        a := colors[index]
        b := colors[index + 1]
        if (a = 0xFFFFFFFF || b = 0xFFFFFFFF)
            return -1
        total += (Abs((a & 0xFF) - (b & 0xFF))
            + Abs(((a >> 8) & 0xFF) - ((b >> 8) & 0xFF))
            + Abs(((a >> 16) & 0xFF) - ((b >> 16) & 0xFF))) / 3
        pairs += 1
        index += 2
    }
    return total / pairs
}

ProbePixels(colors) {
    result := ""
    for color in colors
        result .= (result = "" ? "" : " | ") ProbeRgb(color)
    return result
}
