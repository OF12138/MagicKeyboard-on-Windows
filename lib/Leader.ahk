/*
 * Leader.ahk —— 前导键框架（无界面）
 *
 * 按下前导键 → 再按一个键 → 执行对应动作。
 * 默认什么都不显示；只有按完前导键停顿超过 LEADER_HINT_MS 还没按第二个键，
 * 才用系统原生 ToolTip 列出可用的键（which-key 风格）。按得快就完全无感。
 *
 * 动作定义在 Actions.ahk，本文件只负责「等键、提示、派发」，
 * 加新功能不需要动这里。
 */

LEADER_TIMEOUT := 3        ; 秒，超时自动取消
LEADER_HINT_MS := 600      ; 停顿多久才出提示
LEADER_ON      := false    ; 等第二个键期间为真

LeaderStart() {
    global LEADER_TIMEOUT, LEADER_HINT_MS, LEADER_ON
    if LEADER_ON
        return
    acts := LeaderActions()

    ; 不加 V 选项 = 拦截，第二个键不会打进当前窗口
    ih := InputHook("L1 T" LEADER_TIMEOUT)
    ih.KeyOpt("{Escape}", "E")
    hint := () => ToolTip(LeaderHintText(acts))
    LEADER_ON := true
    SetTimer(hint, -LEADER_HINT_MS)
    ih.Start()
    ih.Wait()
    SetTimer(hint, 0)
    ToolTip()
    LEADER_ON := false

    key := StrLower(ih.Input)
    if (ih.EndReason != "Max" || key = "")
        return                           ; Esc / 超时

    for a in acts {
        if (a.key = key) {
            ; 必须写成 (a.run)() 而不是 a.run() —— 后者是方法调用语法，
            ; 会把 a 当隐式第一参数传进零参数的 lambda，报参数过多。
            try (a.run)()
            catch as e {
                ToolTip("执行失败：" e.Message)
                SetTimer(() => ToolTip(), -2500)
            }
            return
        }
    }
    ; 未定义的键：静默取消
}

LeaderHintText(acts) {
    s := ""
    for a in acts
        s .= StrUpper(a.key) "   " a.label "`n"
    return s "Esc  取消"
}
