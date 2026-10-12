#Requires AutoHotkey v2.0
#SingleInstance Force
InstallKeybdHook

/*
 * 键位探测器
 * 记录 AHK 键盘钩子能看到的每一个按键（含 VK / SC 扫描码）。
 * 用途：确认哪些键可被重映射、哪些键对 Windows 完全不可见（如 Apple fn）。
 */

LOGFILE := A_ScriptDir "\keyprobe.log"
try FileDelete(LOGFILE)
FileAppend("按键探测记录  " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n"
         . "序号  键名                 VK    SC`n"
         . "----  -------------------  ----  ----`n", LOGFILE, "UTF-8")

N := 0

g := Gui("+AlwaysOnTop -MinimizeBox", "键位探测中")
g.SetFont("s11", "Consolas")
g.Add("Text", "w460", "按下要测试的键，结果会实时显示在下面。`n完全没有反应 = Windows 看不到这个键，无法重映射。")
LV := g.Add("ListView", "w460 r14", ["#", "键名", "VK", "SC"])
LV.ModifyCol(1, 40), LV.ModifyCol(2, 220), LV.ModifyCol(3, 80), LV.ModifyCol(4, 80)
g.Add("Button", "w460", "完成并关闭").OnEvent("Click", (*) => ExitApp())
g.OnEvent("Close", (*) => ExitApp())
g.Show()

ih := InputHook("V")          ; V = 不拦截，按键照常送给前台窗口
ih.KeyOpt("{All}", "N")       ; N = 所有键都通知
ih.OnKeyDown := LogKey
ih.Start()

LogKey(hook, vk, sc) {
    global N, LOGFILE, LV
    N++
    name := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    if (name = "")
        name := "(未知)"
    row := [N, name, Format("{:02X}", vk), Format("{:03X}", sc)]
    LV.Add(, row*)
    LV.Modify(N, "Vis")
    FileAppend(Format("{:4}  {:-19}  {:4}  {:4}`n", N, name, row[3], row[4]), LOGFILE, "UTF-8")
}
