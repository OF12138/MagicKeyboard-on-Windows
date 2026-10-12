#Requires AutoHotkey v2.0
#SingleInstance Force

/*
 * 按键间隔测量 —— 用来给去抖阈值定一个有依据的值。
 *
 * 要区分两件事：
 *   A) 固件重复：按 fn+字母 时，同一次按键被发成两个事件
 *   B) 正常连打：你手动快速连按同一个键
 * 阈值必须卡在 A 的上界和 B 的下界之间。已知 A 的范围是 15~109ms，
 * 而 B 的下界未知 —— 这个脚本就是来测 B 的。
 *
 * 指引直接显示在窗口里，不需要去别处看说明。
 */

LOGFILE := A_ScriptDir "\gaptest.log"
try FileDelete(LOGFILE)

phase := 1
gaps  := [[], []]          ; gaps[1]=正常连打  gaps[2]=fn+键
lastT := 0

STEPS := [
    "第 1 组 / 共 2 组　——　正常连打（不要碰 fn）`n`n"
  . "把手放在键盘上，【尽你最快速度】连按 c 键 20 次左右。`n"
  . "这一组决定阈值的上限：阈值必须比你的最快连打间隔更小，`n"
  . "否则会把你真实的连打当成重复吃掉。`n`n"
  . "按够了就点下面的按钮。",

    "第 2 组 / 共 2 组　——　重现 fn 重复`n`n"
  . "用会出双字符的那种按法（fn 和 c 几乎同时按）重复 15 次左右。`n"
  . "如果某次没出现重复也没关系，脚本会自动区分。`n`n"
  . "按够了就点下面的按钮。"
]

g := Gui("+AlwaysOnTop", "按键间隔测量")
g.SetFont("s11", "Segoe UI")
Tip := g.Add("Text", "w620 r9", STEPS[1])
g.SetFont("s10", "Consolas")
Stat := g.Add("Text", "w620 r3", "已记录：0 个间隔")
g.SetFont("s11", "Segoe UI")
Btn := g.Add("Button", "w620 h40", "这一组按完了 →")
Btn.OnEvent("Click", NextPhase)
g.OnEvent("Close", (*) => ExitApp())
g.Show()

ih := InputHook("V")
ih.KeyOpt("{All}", "N")
ih.OnKeyDown := OnKey
ih.Start()

OnKey(hook, vk, sc) {
    global phase, gaps, lastT, Stat
    if (vk != 0x43)                    ; 只统计 c 键，避免别的按键混进来
        return
    now := A_TickCount
    if (lastT) {
        d := now - lastT
        if (d < 2000)                  ; 超过 2 秒视为新一轮，不计入
            gaps[phase].Push(d)
    }
    lastT := now
    Stat.Text := "已记录：" gaps[phase].Length " 个间隔"
        . (gaps[phase].Length ? "`n最近：" Join(Last(gaps[phase], 12)) : "")
}

Last(arr, n) {
    out := []
    start := Max(1, arr.Length - n + 1)
    loop arr.Length - start + 1
        out.Push(arr[start + A_Index - 1])
    return out
}
Join(arr) {
    s := ""
    for v in arr
        s .= v "ms  "
    return s
}

NextPhase(*) {
    global phase, gaps, lastT, Tip, Stat, Btn, STEPS
    if (phase = 1) {
        phase := 2, lastT := 0
        Tip.Text := STEPS[2]
        Stat.Text := "已记录：0 个间隔"
        Btn.Text := "测完，出结果 →"
        return
    }
    Report()
}

Report() {
    global gaps, LOGFILE, Tip, Stat, Btn
    a := gaps[1], b := gaps[2]
    if (a.Length < 5 || b.Length < 5) {
        Tip.Text := "两组样本都至少需要 5 个间隔。`n"
                  . "第 1 组 " a.Length " 个，第 2 组 " b.Length " 个。`n请补测。"
        return
    }

    ; 正常连打：取最小值，这是阈值不能越过的红线
    aMin := Min(a*), aP10 := Pct(a, 10)
    ; fn 组里明显偏小的那一簇 = 固件重复
    dup := [], real := []
    for v in b
        (v < aMin ? dup.Push(v) : real.Push(v))
    dupMax := dup.Length ? Max(dup*) : 0

    ; 阈值取「重复上界」和「连打下界」的中点，并留出余量
    thr := dupMax ? Floor((dupMax + aMin) / 2) : Floor(aMin * 0.6)

    txt := "=== 结果 ===`n`n"
         . "正常连打（" a.Length " 个样本）：最小 " aMin "ms   10% 分位 " aP10 "ms`n"
         . "fn 组（" b.Length " 个样本）：疑似重复 " dup.Length " 个，最大 " dupMax "ms`n`n"
         . "建议去抖阈值：" thr " ms`n`n"
         . (dupMax >= aMin
            ? "⚠ 两者区间重叠，无法完全分开 —— 纯时间去抖会有误伤"
            : "✓ 两者区间不重叠，阈值安全")
    Tip.Text := txt
    Stat.Text := "正常连打: " Join(a) "`nfn 组: " Join(b)
    Btn.Text := "关闭"
    Btn.OnEvent("Click", (*) => ExitApp())

    FileAppend(txt "`n`n正常连打间隔: " Join(a) "`nfn 组间隔: " Join(b) "`n", LOGFILE, "UTF-8")
}

Pct(arr, p) {
    s := []
    for v in arr
        s.Push(v)
    ; 简单插入排序，样本量很小
    loop s.Length - 1 {
        i := A_Index + 1
        while (i > 1 && s[i] < s[i-1]) {
            t := s[i], s[i] := s[i-1], s[i-1] := t
            i--
        }
    }
    idx := Max(1, Round(s.Length * p / 100))
    return s[idx]
}
