#Requires AutoHotkey v2.0
#SingleInstance Force
InstallKeybdHook

/*
 * 按键释放顺序统计
 *
 * 用途：确认「修饰键 + 字母」这个手势里，你是先松修饰键还是先松字母。
 * 这决定了 fn 误触能不能被检测到 —— 键盘只在【字母仍按着时松开 fn】
 * 的情况下才会重发那个字母。
 *
 * 不拦截任何按键，正常打字工作不受影响。
 */

LOGFILE := A_ScriptDir "\habit.log"
try FileDelete(LOGFILE)

modDown  := Map()      ; 修饰键当前是否按着
active   := ""         ; 当前手势里的字母（空=没有进行中的手势）
activeMod := ""
modFirst := 0          ; 先松修饰键的次数
keyFirst := 0          ; 先松字母的次数
seq      := []         ; 当前手势的事件序列，用于展示

MODS := Map("LControl","Ctrl(左)", "RControl","Ctrl(右)"
          , "LWin","Win(左)", "RWin","Win(右)"
          , "LAlt","Alt(左)", "RAlt","Alt(右)"
          , "LShift","Shift(左)", "RShift","Shift(右)")

g := Gui("+AlwaysOnTop", "释放顺序统计")
g.SetFont("s11", "Segoe UI")
g.Add("Text", "w600",
    "请按你平时的习惯，做 10 次左右【修饰键 + 字母】的操作，`n"
  . "比如 Ctrl+C、Ctrl+V、Ctrl+Z、Ctrl+A（用真正的 control 键，不是 fn）。`n"
  . "正常操作即可，脚本不拦截按键。")
g.SetFont("s14 w600", "Segoe UI")
Score := g.Add("Text", "w600 r2", "先松修饰键：0 次　　先松字母：0 次")
g.SetFont("s10", "Consolas")
Seqs := g.Add("Edit", "w600 r10 ReadOnly -WantReturn")
g.SetFont("s11", "Segoe UI")
g.Add("Button", "w600 h36", "完成并关闭").OnEvent("Click", (*) => Finish())
g.OnEvent("Close", (*) => Finish())
g.Show()

ih := InputHook("V")
ih.KeyOpt("{All}", "N")
ih.OnKeyDown := Down
ih.OnKeyUp := Up
ih.Start()

Name(vk, sc) => GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))

Down(hook, vk, sc) {
    global modDown, active, activeMod, seq, MODS
    n := Name(vk, sc)
    if (MODS.Has(n)) {
        modDown[n] := true
        if (!active)
            seq := ["↓" MODS[n]]
        return
    }
    ; 字母键，且有修饰键按着 → 开始一个手势
    if (StrLen(n) = 1 && !active) {
        for m, label in MODS {
            if (modDown.Get(m, false)) {
                active := n, activeMod := m
                seq.Push("↓" n)
                return
            }
        }
    }
}

Up(hook, vk, sc) {
    global modDown, active, activeMod, modFirst, keyFirst, seq, Score, Seqs, MODS
    n := Name(vk, sc)

    if (MODS.Has(n)) {
        modDown[n] := false
        if (active && n = activeMod) {
            seq.Push("↑" MODS[n])
            modFirst++
            Record("先松修饰键")
        }
        return
    }
    if (active && n = active) {
        seq.Push("↑" n)
        if (modDown.Get(activeMod, false)) {
            keyFirst++
            Record("先松字母")
        } else
            Flush()          ; 修饰键已经先松过了，这里只是收尾
    }
}

Record(verdict) {
    global seq, Score, modFirst, keyFirst, active, activeMod
    Score.Text := "先松修饰键：" modFirst " 次　　先松字母：" keyFirst " 次"
    Seqs.Value := Trim(verdict "  " JoinSeq() "`n" Seqs.Value, "`n")
    FileAppend(verdict "  " JoinSeq() "`n", A_ScriptDir "\habit.log", "UTF-8")
    active := "", activeMod := "", seq := []
}
Flush() {
    global active, activeMod, seq
    active := "", activeMod := "", seq := []
}
JoinSeq() {
    global seq
    s := ""
    for v in seq
        s .= v "  "
    return s
}

Finish() {
    global modFirst, keyFirst
    total := modFirst + keyFirst
    if (total = 0) {
        ExitApp()
        return
    }
    pct := Round(100 * modFirst / total)
    txt := "共 " total " 次`n先松修饰键 " modFirst " 次（" pct "%）`n先松字母 " keyFirst " 次`n`n"
         . (pct >= 70
            ? "→ 你的习惯是【先松修饰键】。fn 误触会产生可检测的重复信号。"
            : pct <= 30
              ? "→ 你的习惯是【先松字母】。fn 误触【不会】产生重复信号，检测不可行。"
              : "→ 两种都有，检测只能覆盖一部分。")
    FileAppend("`n" txt "`n", A_ScriptDir "\habit.log", "UTF-8")
    MsgBox(txt, "统计结果", "Iconi")
    ExitApp()
}
