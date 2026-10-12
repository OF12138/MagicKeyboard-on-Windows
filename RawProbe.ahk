#Requires AutoHotkey v2.0
#SingleInstance Force

/*
 * Raw Input 探测器
 *
 * 键盘钩子只能看到 Windows 已翻译成虚拟键的输入。消费类控制
 * （音量、媒体）走的是另一条路：HID Usage Page 0x0C。
 * 这里直接注册 Raw Input 收原始报文，看键盘到底发出了什么。
 */

LOGFILE := A_ScriptDir "\rawprobe.log"
try FileDelete(LOGFILE)
FileAppend("Raw Input 探测  " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n`n", LOGFILE, "UTF-8")

N := 0

g := Gui("+AlwaysOnTop -MinimizeBox", "Raw Input 探测中")
g.SetFont("s10", "Consolas")
g.Add("Text", "w560",
    "请用会出双字符的那种按法，快速按 fn + c 重复 6~8 次。`n"
  . "现在按下和抬起都会记录，用来看固件重复的事件序列到底长什么样。`n"
  . "按完点「完成并关闭」。")
LV := g.Add("ListView", "w560 r16", ["#", "来源", "UsagePage", "报文(hex)"])
LV.ModifyCol(1, 40), LV.ModifyCol(2, 90), LV.ModifyCol(3, 90), LV.ModifyCol(4, 320)
g.Add("Button", "w560", "完成并关闭").OnEvent("Click", (*) => ExitApp())
g.OnEvent("Close", (*) => ExitApp())
g.Show()

; ---- 注册 Raw Input ----
; RAWINPUTDEVICE: USHORT usUsagePage; USHORT usUsage; DWORD dwFlags; HWND hwndTarget
; x64 下因对齐为 16 字节
RIDEV_INPUTSINK := 0x00000100        ; 即使不在前台也收
pages := [[0x0C, 0x01, "消费类"]     ; Consumer Control —— 音量/媒体键走这里
        , [0x01, 0x06, "键盘"]       ; 标准键盘，用作对照
        , [0x01, 0x80, "系统控制"]]  ; System Control —— 电源/锁定可能走这里

rid := Buffer(16 * pages.Length, 0)
for i, p in pages {
    off := (i - 1) * 16
    NumPut("ushort", p[1], rid, off + 0)
    NumPut("ushort", p[2], rid, off + 2)
    NumPut("uint", RIDEV_INPUTSINK, rid, off + 4)
    NumPut("ptr", A_ScriptHwnd, rid, off + 8)
}
ok := DllCall("RegisterRawInputDevices", "ptr", rid, "uint", pages.Length, "uint", 16, "int")
FileAppend("RegisterRawInputDevices -> " (ok ? "成功" : "失败 " A_LastError) "`n`n", LOGFILE, "UTF-8")

OnMessage(0x00FF, OnRawInput)        ; WM_INPUT

OnRawInput(wParam, lParam, msg, hwnd) {
    global N, LOGFILE, LV

    size := 0
    DllCall("GetRawInputData", "ptr", lParam, "uint", 0x10000003   ; RID_INPUT
          , "ptr", 0, "uint*", &size, "uint", 24)                  ; sizeof(RAWINPUTHEADER)=24
    if (size = 0)
        return
    buf := Buffer(size, 0)
    if (!DllCall("GetRawInputData", "ptr", lParam, "uint", 0x10000003
               , "ptr", buf, "uint*", &size, "uint", 24))
        return

    type := NumGet(buf, 0, "uint")   ; 0=鼠标 1=键盘 2=HID

    if (type = 2) {                  ; RIM_TYPEHID —— 消费类/系统控制走这里
        szHid := NumGet(buf, 24, "uint")
        cnt   := NumGet(buf, 28, "uint")
        hex := ""
        loop (szHid * cnt)
            hex .= Format("{:02X} ", NumGet(buf, 32 + A_Index - 1, "uchar"))
        Log("HID", "0x0C/0x80", Trim(hex))
    } else if (type = 1) {           ; RIM_TYPEKEYBOARD
        ; RAWKEYBOARD 在偏移 24：MakeCode(2) Flags(2) Reserved(2) VKey(2) Message(4) ExtraInfo(4)
        mk  := NumGet(buf, 24, "ushort")
        fl  := NumGet(buf, 26, "ushort")
        vk  := NumGet(buf, 30, "ushort")
        ; 按下和【抬起】都要记 —— 去抖逻辑靠「两次按下之间有没有抬起」
        ; 来区分固件重复和系统自动重复，这个假设必须用数据验证。
        kind := (fl & 1) ? "↑抬起" : "↓按下"
        Log("键盘", "0x01/0x06", Format("{}  VK={:02X} SC={:03X} {}"
            , kind, vk, mk, GetKeyName(Format("vk{:02X}", vk))))
    }
}

Log(src, page, text) {
    global N, LOGFILE, LV
    static lastTick := 0, lastText := ""
    N++
    now := A_TickCount
    delta := lastTick ? (now - lastTick) : 0
    ; 同一个键在极短间隔内重复出现，是我们要抓的目标
    flag := (delta > 0 && delta < 60 && text = lastText) ? "  <<< 疑似重复" : ""
    lastTick := now, lastText := text

    LV.Add(, N, src, page, text "  (+" delta "ms)" flag)
    LV.Modify(N, "Vis")
    FileAppend(Format("{:4}  {:-6}  {:-10}  {:-28}  +{:5}ms{}`n"
                    , N, src, page, text, delta, flag), LOGFILE, "UTF-8")
}
