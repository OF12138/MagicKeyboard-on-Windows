#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

#Include %A_ScriptDir%\Actions.ahk
#Include %A_ScriptDir%\lib\Leader.ahk
#Include %A_ScriptDir%\lib\Glass.ahk

/*
 * Magic Keyboard on Windows —— 交换 Alt / Win 的物理位置
 *
 *   Magic Keyboard :  fn  control  option   command  [Space]
 *   原生映射       :       Ctrl     Alt      Win
 *   PC 键盘布局    :       Ctrl     Win      Alt
 *                                   ↑         ↑   交换这两个
 *
 * 退出脚本 = 立即完全还原，不碰注册表、不碰驱动、不需要重启。
 */

; ===== 配置 =====
; 同一把键盘在两种连接方式下的身份完全不同，要分别检测：
;   蓝牙  VID 0x004C（Apple 的 Bluetooth SIG 厂商号），查链路连接状态
;   有线  VID 0x05AC（Apple 的 USB 厂商号），查设备是否在场
; PID 都是 0x0320。
KB_ADDR := 0                ; 蓝牙 MAC（已脱敏）
KB_USB  := "HID\VID_05AC&PID_0320"   ; 有线时的 HID 设备前缀
POLL_MS := 2000             ; 两种查询合计约 3ms，2 秒一轮开销可忽略
MODE    := "auto"           ; auto=跟随连接状态（蓝牙或有线）/ on=强制开 / off=强制关
NOTIFY  := true
; 这些程序运行期间脚本整体让路：停用所有热键并卸掉键盘钩子，对它们完全不可见。
; 原神的反作弊会干预键盘输入，和钩子同时存在时出现过 Win 键卡住。
; 国服 YuanShen.exe，国际服 GenshinImpact.exe。
GAME_EXES := ["YuanShen.exe", "GenshinImpact.exe"]
GAME_ON   := ""             ; 当前在运行的那个游戏，由 Refresh 维护
ACTIVE  := false            ; 由 Refresh 维护，勿手改

; ===== fn 误触去抖 =====
; 机理（逐键观察确认，不是猜的）：
;      按 fn    → 无事发生（fn 对 Windows 完全不可见）
;      按 c     → 正常输出一个 c
;      松开 fn  → 键盘把仍按着的 c【重新发一次按下】，于是多出一个 c
;      松开 c   → 无事发生
; 事件序列是 down-down-up：两次按下、一次抬起，中间没有抬起。
;
; 关键推论：第二次按下距第一次多久，完全取决于 fn 被握了多久，
; 可能 50ms 也可能 800ms。**任何基于时间阈值的判据都必然失效** ——
; 这条路我试过两版，都漏。
;
; 可靠的区别是【周期性】：
;      系统自动重复 = 连续的一串，本机首次延迟 500ms，之后每 33ms 一个
;      fn 松开重复   = 孤立的一个，后面没有了
; 做法：按住期间的第一个额外按下一律先吞掉；若在 REPEAT_PERIOD_MS 内
; 又来一个，说明是成串的自动重复，转为全部放行。
; 代价是自动重复会少掉第一个字符，几乎感知不到。
;
; DEBOUNCE_MS 只用于「键已抬起后」的兜底，防备 down-up-down 形态。
; 依据 GapTest.ahk：正常连打最小 125ms，快速误触重复最大 94ms，取 105ms 居中。
;
; 只保护左手区 —— fn 被误按的唯一场景是把它当成 Ctrl，
; 而 Ctrl 组合基本都落在这片。其他键不去抖，误伤面积接近零。
DEBOUNCE_MS     := 105
REPEAT_PERIOD_MS := 120   ; 自动重复间隔 33ms，放宽到 120ms 容错
DEBOUNCE_KEYS   := "qwertasdfgzxcvb"

; ===== 误触自动补救 =====
; 检测到 fn 重复时，说明刚才那个字符是误触打出来的，而且你本意是 Ctrl+该键。
; 此刻破坏【已经发生】（比如选中的文本已被字符覆盖），无论如何都要撤销，
; 所以真正的取舍是「自动撤销」对「手动撤销」，不是「有风险」对「无风险」。
;
; 补救动作：Ctrl+Z 撤销误打的字符，再补发本来想要的 Ctrl+该键。
; 用 Ctrl+Z 而不是退格 —— 「替换选中内容」在文本控件里是一次可撤销操作，
; Ctrl+Z 能连选区一起恢复；退格只删字符，选区回不来。
;
; 覆盖率：实测你 91% 的操作是先松修饰键（会产生信号），
; 剩下 9% 集中在 a/s（Ctrl 离得近，手势不同）。检测不到时不动作，
; 退化成手动处理，不会做错事。
RECOVER      := true
RECOVER_KEYS := "cvxazs"      ; 只补救这几个。故意不含 q/w/r/t ——
                              ; 误判时 Ctrl+Q 退出、Ctrl+W 关标签，代价太大
RECOVER_SKIP := "explorer.exe"  ; 资源管理器里 Ctrl+Z 会撤销文件操作，危险

; ===== 映射本体 =====
; #HotIf 让这组重映射只在 ACTIVE 为真时存在；为假时一个钩子都不触发，
; 键盘回到完全原生的行为。
#HotIf IsActive()
LAlt::LWin      ; option  → Win
LWin::LAlt      ; command → Alt
RAlt::RWin
RWin::RAlt

; --- F1~F10 → 键帽图标对应的 Windows 功能 ---
; 这里用的是「裸键」热键（没有 * 前缀），AHK 要求修饰键完全匹配，
; 所以 Ctrl+F5 / Shift+F3 / Alt+F4 这类组合会原样透传给应用，
; 只有单独按下 F 键才会触发下面的功能。不想要哪个，注释掉即可。
F1::Brightness(-10)              ; 🔅 亮度 −
F2::Brightness(+10)              ; 🔆 亮度 +
F3::Send("#{Tab}")               ; 调度中心 → 任务视图
F4::LeaderStart()               ; 🔍 前导键：F4 → 再按一个键，动作表见 Actions.ahk
F5::Send("#h")                   ; 听写     → 语音输入
F6::Send("#n")                   ; 勿扰     → 通知中心（Win 无勿扰快捷键，这是最接近的）
F7::Send("{Media_Prev}")         ; ⏮
F8::Send("{Media_Play_Pause}")   ; ⏯
F9::Send("{Media_Next}")         ; ⏭
F10::Send("{Volume_Mute}")       ; 🔇
F11::Send("{Volume_Down}")       ; 🔉
F12::Send("{Volume_Up}")         ; 🔊
#HotIf

; 状态必须跨函数共享。写成两个函数各自的 static 是错的 ——
; 那样会变成两份互不相干的副本，按下和抬起对不上。
;
; 这几行必须在 UpdateTray() 之前 —— AHK 顶层语句按书写顺序执行，
; 放在函数定义区（文件后半部分）会导致 UpdateTray 读到未赋值的变量，
; 启动时直接弹错误框。/validate 只查语法，查不出这种时序问题。
DB_LAST    := Map()    ; 上一次【被放行】的按下时刻
DB_HELD    := Map()    ; 物理键当前是否按着
DB_REPEAT  := Map()    ; 本次按住是否已进入系统自动重复
DB_SENT    := Map()    ; 本次按住是否真的发出过按下（决定抬起要不要发）
DB_SUSPECT := Map()    ; 按住期间第一个可疑按下的时刻（用来判断后面是否成串）
DB_FIXED   := 0        ; 累计自动补救次数（只在托盘提示里显示，不弹窗）

; 注意必须显式 global —— 函数里未声明的变量默认是局部的，
; 直接写 ACTIVE 会读到一个未赋值的局部变量（= 假），热键永远不触发。
; 必须写成 (*) 接受任意参数 —— HotIf 的回调会被传入热键名，
; 零参数的函数会被拒绝并报 "Invalid callback function"，
; 而那个错误框会阻塞整个自动执行段，连 Refresh() 都跑不到。
IsActive(*) {
    global ACTIVE
    return ACTIVE
}

; 去抖热键的条件：前导键等第二个键时让路，否则 F4 → c 的 c
; 会被去抖热键截走，到不了 InputHook。
DebounceOn(*) {
    global ACTIVE, LEADER_ON
    return ACTIVE && !LEADER_ON
}

; 修饰键卡住防护的参数，说明见下方「修饰键卡住防护」一节。
; 必须放在 InstallStuckGuard() 之前 —— 顶层语句按书写顺序执行。
STUCK_IDLE_MS := 3000
STUCK_MODS    := ["LWin", "RWin", "LAlt", "RAlt"]
; 钩子存活检测的参数和状态，说明见「键盘钩子存活检测」一节
HOOK_DEAD_MS := 1000
RAW_TICK  := 0          ; Raw Input 最近一次看到去抖字母按下的时刻
HOOK_TICK := 0          ; 钩子热键最近一次处理去抖字母的时刻（DebounceDown 里更新）
; 主线程卡顿记录的参数，说明见「主线程卡顿记录」一节
STALL_TICK_MS := 100
STALL_LOG_MS  := 250
STALL_LAST    := 0
; 左 Shift 单按切换中英文的状态，说明见「左 Shift 单按切换中英文」一节
LSHIFT_HELD   := false
LSHIFT_LATE   := false

; ===== 事件日志 =====
; 只记事件（启动、映射开关、锁屏/解锁、睡眠/唤醒、修饰键卡住），不记按键内容。
; 正常一天几十行；超过 512 KB 自动轮换成 .old。
EVENT_LOG := A_ScriptDir "\events.log"
LogEvent(t) {
    global EVENT_LOG
    try {
        if FileExist(EVENT_LOG) && FileGetSize(EVENT_LOG) > 512 * 1024
            FileMove(EVENT_LOG, EVENT_LOG ".old", 1)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " t "`n", EVENT_LOG, "UTF-8")
    }
}

; 按键历史默认只留 40 个，出问题后一打字就被冲掉。托盘「按键历史」可查看。
KeyHistory(500)

BuildTray()
UpdateTray()
InstallDebounce()
LogEvent("启动")
SetTimer(Refresh, POLL_MS)
Refresh()
InstallStuckGuard()
InstallHookWatch()
SetTimer(StallCheck, STALL_TICK_MS)

; 说明：这里只能轮询，不能用 WM_DEVICECHANGE。
; 实测证明键盘断电时设备节点毫无变化（IsPresent 恒为 True），
; 根本不会产生 devnode 变更事件。详见 README「为什么必须轮询」。

; 外层只负责计时：Refresh 跑在主线程上，卡久了会拖垮钩子（见「主线程卡顿记录」）
Refresh(*) {
    t0 := A_TickCount
    RefreshInner()
    if ((dt := A_TickCount - t0) >= 100)
        LogEvent("Refresh 耗时 " dt "ms")
}

RefreshInner() {
    global MODE, ACTIVE, NOTIFY, KB_ADDR, GAME_EXES, GAME_ON

    ; --- 游戏让路 ---
    ; 用 Suspend 而不是只把 ACTIVE 置假：ACTIVE 为假时热键不触发，但钩子仍然挂着；
    ; Suspend 后没有任何热键需要钩子，AHK 会把它整个卸掉。
    game := ""
    for exe in GAME_EXES
        if ProcessExist(exe) {
            game := exe
            break
        }
    if (game != GAME_ON) {
        GAME_ON := game
        if (game != "") {
            ReleaseMods("游戏启动前")
            Suspend(true)
            ACTIVE := false
            LogEvent("检测到 " game "，脚本暂停")
        } else {
            Suspend(false)
            LogEvent("游戏已退出，脚本恢复")
        }
        UpdateTray()
    }
    if (GAME_ON != "")
        return

    if (MODE = "on")
        want := true
    else if (MODE = "off")
        want := false
    else {
        ; 有线优先判断：USB 在场就直接生效，连蓝牙都不用查。
        ; 插线时键盘会断开蓝牙，此时 BtConnected 必然返回 0，
        ; 所以顺序不能反，否则有线会被误判成未连接。
        if (UsbPresent())
            want := true
        else {
            conn := BtConnected(KB_ADDR)
            if (conn = -1)      ; 查询失败：保持现状，避免来回抖动
                return
            want := (conn = 1)
        }
    }

    if (want = ACTIVE)
        return
    ACTIVE := want
    LogEvent("映射" (ACTIVE ? "开启" : "关闭") "（模式 " MODE "）")

    ; 切换瞬间如果正按着修饰键，可能留下粘键，统一松开一次
    for k in ["LAlt", "RAlt", "LWin", "RWin"]
        Send("{" k " up}")

    UpdateTray()
    if (NOTIFY)
        TrayTip(ACTIVE ? "Alt / Win 已交换" : "已还原为原生布局", "Magic Keyboard", 0x10)
}

; ===== 修饰键卡住防护 =====
; 症状：command 和 option 都变成 Win。本质是系统里的 LWin 一直处于「按下」。
;
; 机理：option 被映射成 LWin，按下时脚本发出 LWin↓，要等 option 松开时才发 LWin↑。
; 如果 option 的松开事件没被脚本看到，LWin 就永远不松。此后按任何键都带着 Win，
; command（→ Alt）也就成了 Win+Alt。直到下次按 option，一对新的↓↑把它带松，
; 所以表现为「过一会儿自己好了」。
;
; 松开事件看不到的典型场景：
;   · option+L 锁屏 —— 锁屏界面在安全桌面上，低级键盘钩子收不到那边的按键
;   · UAC 弹窗、Ctrl+Alt+Del，同理
;   · 睡眠 / 唤醒、USB 瞬断：设备消失时按键的松开根本没发生
;
; 两道防线：
;   1. 解锁、唤醒时主动松开所有被映射的修饰键
;   2. 看门狗：系统认为修饰键按着，但物理键盘已经 STUCK_IDLE_MS 没有任何输入
;      —— 真按着的键会持续自动重复，不可能这么久没有事件，判定为卡住
InstallStuckGuard() {
    ; 锁屏/解锁通知
    DllCall("wtsapi32\WTSRegisterSessionNotification", "ptr", A_ScriptHwnd, "uint", 0)
    OnMessage(0x02B1, OnSessionChange)    ; WM_WTSSESSION_CHANGE
    OnMessage(0x0218, OnPowerChange)      ; WM_POWERBROADCAST
    SetTimer(StuckCheck, 500)
}

; ===== 键盘钩子存活检测 =====
; 实测出现过两次：脚本进程在、热键都登记着、ACTIVE=1，但 KeyHistory 显示
; "Keybd hook: no" —— 钩子在运行途中丢了，映射全部静默失效，脚本自己毫无察觉。
; 两次都是重启脚本即恢复。在解锁/唤醒时强制重装钩子（InstallKeybdHook(true, true)）
; 试过，无效 —— 日志显示重装照做了，钩子照样丢。原因未查明。
;
; 所以改为【检测】：Raw Input 是和低级钩子完全独立的输入通道，钩子没了它照样收得到。
; 去抖名单里的字母每次按下都必然经过钩子热键 DebounceDown。
; 若 Raw Input 看到了这类按键，而钩子在 HOOK_DEAD_MS 内没有跟上，就判定钩子已死，重启脚本。

InstallHookWatch() {
    ; RAWINPUTDEVICE: usUsagePage(2) usUsage(2) dwFlags(4) hwndTarget(8)
    rid := Buffer(16, 0)
    NumPut("ushort", 0x01, rid, 0)             ; Generic Desktop
    NumPut("ushort", 0x06, rid, 2)             ; Keyboard
    NumPut("uint", 0x100, rid, 4)              ; RIDEV_INPUTSINK：不在前台也收
    NumPut("ptr", A_ScriptHwnd, rid, 8)
    if !DllCall("RegisterRawInputDevices", "ptr", rid, "uint", 1, "uint", 16)
        return LogEvent("Raw Input 注册失败，钩子存活检测未启用")
    OnMessage(0x00FF, OnRawKey)                ; WM_INPUT
    SetTimer(HookWatch, 500)
}

OnRawKey(wParam, lParam, *) {
    global RAW_TICK, DEBOUNCE_KEYS
    static buf := Buffer(64, 0)
    size := 64
    if (DllCall("GetRawInputData", "ptr", lParam, "uint", 0x10000003   ; RID_INPUT
              , "ptr", buf, "uint*", &size, "uint", 24) <= 0)
        return
    if (NumGet(buf, 0, "uint") != 1)           ; 只看 RIM_TYPEKEYBOARD
        return
    if (NumGet(buf, 26, "ushort") & 1)         ; RI_KEY_BREAK = 抬起，不看
        return
    vk := NumGet(buf, 30, "ushort")
    ; 只记【第一个】还没被钩子响应的按键。若每次都刷新，连续打字时这个时刻
    ; 会不断后移，要停手 1 秒才能报出来（实测拖到了 9 秒）。
    global HOOK_TICK
    if (vk >= 0x41 && vk <= 0x5A && InStr(DEBOUNCE_KEYS, Chr(vk + 32)) && DebounceOn()
        && RAW_TICK <= HOOK_TICK + 50)
        RAW_TICK := A_TickCount
}

HookWatch() {
    global RAW_TICK, HOOK_TICK, HOOK_DEAD_MS
    if (!RAW_TICK || HOOK_TICK >= RAW_TICK - 50)          ; 钩子跟上了（两边先后顺序不定，留 50ms 余量）
        return
    if (A_TickCount - RAW_TICK < HOOK_DEAD_MS)            ; 还在等钩子
        return
    if (A_IsSuspended || !DebounceOn() || ForegroundElevated()) {
        RAW_TICK := 0                                     ; 这些情况下钩子本来就看不到，不算
        return
    }
    fg := ""
    try fg := WinGetProcessName("A")
    why := "Raw Input 收到按键，钩子 " (A_TickCount - RAW_TICK) "ms 未响应，前台 " fg

    ; 防止死循环：重启也救不回来时，会在打字过程中每一两秒重启一次。
    ; 上次重启的时刻写在文件里（A_TickCount 是开机以来的毫秒数，跨进程可比）。
    stamp := A_ScriptDir "\.hook-reload"
    last := 0
    try last := Integer(FileRead(stamp))
    if (last && A_TickCount - last < 60000 && A_TickCount > last) {
        LogEvent("检测到键盘钩子失效（" why "），但 60 秒内已重启过一次仍未恢复，停止检测，需手动处理")
        SetTimer(HookWatch, 0)
        return
    }
    try FileDelete(stamp)
    FileAppend(A_TickCount, stamp)
    LogEvent("检测到键盘钩子失效（" why "），重启脚本")
    Reload()
}

; 前台是管理员窗口时，普通权限的钩子本来就收不到按键（UIPI），不能算钩子死了。
; 查不出来的一律当作「是」，宁可漏报也不误重启。
ForegroundElevated() {
    try pid := WinGetPID("A")
    catch
        return true
    h := DllCall("OpenProcess", "uint", 0x1000, "int", 0, "uint", pid, "ptr")   ; QUERY_LIMITED_INFORMATION
    if !h
        return true
    tok := 0, elev := 0, ret := 0
    ok := DllCall("advapi32\OpenProcessToken", "ptr", h, "uint", 0x8, "ptr*", &tok)   ; TOKEN_QUERY
    if ok {
        ok := DllCall("advapi32\GetTokenInformation", "ptr", tok, "int", 20       ; TokenElevation
                    , "uint*", &elev, "uint", 4, "uint*", &ret)
        DllCall("CloseHandle", "ptr", tok)
    }
    DllCall("CloseHandle", "ptr", h)
    return !ok || elev != 0
}

; ===== 主线程卡顿记录 =====
; 钩子频繁失效的机理（AutoHotkey 文档 #HotIfTimeout 一节）：
;   带 #HotIf 条件的热键，每次按键都要由钩子线程回到主线程求值条件。
;   主线程正忙时钩子就跟着等，AHK 自己最多等 1000ms；
;   而 Windows 给低级钩子的时限默认只有 300ms，超时 10 次以内放过，第 11 次直接把钩子摘掉。
;   本脚本几乎所有热键都带条件（IsActive / DebounceOn），打字时每个字母都要回主线程一次。
; 所以主线程每卡一次 300ms 以上，都可能记一次超时，累计 11 次钩子就没了。
; 这里只负责记录主线程什么时候卡、卡多久，用来找出是谁在卡。
StallCheck() {
    global STALL_LAST, STALL_TICK_MS, STALL_LOG_MS
    now := A_TickCount
    gap := now - STALL_LAST - STALL_TICK_MS
    ; 超过 30 秒的间隔是睡眠，不是卡顿
    if (STALL_LAST && gap >= STALL_LOG_MS && gap < 30000) {
        fg := ""
        try fg := WinGetProcessName("A")
        LogEvent("主线程卡顿 " gap "ms（前台 " fg "，空闲 " A_TimeIdlePhysical "ms）")
    }
    STALL_LAST := now
}

; ===== 左 Shift 单按切换中英文 =====
; 微软拼音自己也会在「单按 Shift」时切换，但它的判断偶尔漏。改由脚本来切：
;   1. Shift 按下时补发一个未分配的虚拟键 vkE8，输入法看到 Shift 和别的键组合过，就不会自己再切；
;   2. Shift 松开时，若这期间没有按过别的键，脚本直接调用输入法接口切换。
;      和输入法原生行为一致，不限按住时长（实测原生按住 800ms 也会切）。
; 带 ~ 前缀，Shift 本身照常传给系统，Shift+字母、Ctrl+Shift+T 这些组合完全不受影响。
; 不加 #HotIf 条件：不用回主线程求值，不会拖累钩子；只在脚本暂停（游戏）时停用，
; 那时输入法自己的 Shift 切换照常生效。
~LShift:: {
    global LSHIFT_HELD, LSHIFT_LATE
    if LSHIFT_HELD                 ; 按住不放时的自动重复
        return
    LSHIFT_HELD := true
    ; 主线程忙时这里会晚到。若 Shift 此刻已经松开，vkE8 赶不上了，输入法会自己切，
    ; 脚本就不能再切一次（两次等于没切）。自动化测试里偶发过单按没切换。
    LSHIFT_LATE := !(DllCall("GetAsyncKeyState", "int", 0xA0, "short") & 0x8000)
    if !LSHIFT_LATE
        Send("{Blind}{vkE8}")
}

~LShift up:: {
    global LSHIFT_HELD, LSHIFT_LATE
    LSHIFT_HELD := false
    if LSHIFT_LATE
        return
    ; A_PriorKey 不含脚本自己发出的按键，所以 vkE8 不会干扰这里的判断
    ; Ctrl/Alt/Win 按着时点 Shift 属于组合键，不切
    if (A_PriorKey = "LShift"
        && !GetKeyState("Ctrl") && !GetKeyState("Alt") && !GetKeyState("LWin") && !GetKeyState("RWin"))
        ImeToggle()
}

; 切换焦点控件的中/英文模式。微软拼音实测：中文 = 1025（NATIVE|SYMBOL），英文 = 0；
; 只翻 NATIVE 位写成 1024 会被它忽略，必须整值写入。
; 经输入法的默认窗口发 WM_IME_CONTROL，用 SendMessageTimeout，对方无响应时最多等 100ms，不卡主线程。
ImeToggle() {
    focus := FocusHwnd()
    if !focus
        return
    ime := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", focus, "ptr")
    if !ime
        return
    conv := 0
    if !DllCall("SendMessageTimeoutW", "ptr", ime, "uint", 0x283, "ptr", 0x001, "ptr", 0   ; IMC_GETCONVERSIONMODE
              , "uint", 0x2, "uint", 100, "ptr*", &conv)                                  ; SMTO_ABORTIFHUNG
        return
    DllCall("SendMessageTimeoutW", "ptr", ime, "uint", 0x283, "ptr", 0x002, "ptr", (conv & 1) ? 0 : 1025 ; IMC_SETCONVERSIONMODE
          , "uint", 0x2, "uint", 100, "ptr*", 0)
}

; 前台窗口里拥有键盘焦点的控件。输入上下文挂在它上面，不是顶层窗口。
; GUITHREADINFO 在 x64 下 72 字节，hwndFocus 在偏移 16。
FocusHwnd() {
    hwnd := DllCall("GetForegroundWindow", "ptr")
    if (!hwnd)
        return 0
    gti := Buffer(72, 0)
    NumPut("uint", 72, gti, 0)
    tid := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    if (DllCall("GetGUIThreadInfo", "uint", tid, "ptr", gti, "int"))
        if (f := NumGet(gti, 16, "ptr"))
            return f
    return hwnd
}

OnSessionChange(wParam, *) {
    if (wParam = 7)
        LogEvent("锁屏")
    else if (wParam = 8) {
        LogEvent("解锁")
        ReleaseMods("解锁")
    }
}

OnPowerChange(wParam, *) {
    if (wParam = 4)
        LogEvent("睡眠")
    else if (wParam = 7 || wParam = 0x12) {
        LogEvent("唤醒")
        ReleaseMods("唤醒")
    }
}

; 系统（不是脚本自己）眼中哪些修饰键是按下的
ModsDown() {
    global STUCK_MODS
    down := []
    for k in STUCK_MODS
        if (DllCall("GetAsyncKeyState", "int", GetKeyVK(k), "short") & 0x8000)
            down.Push(k)
    return down
}

ReleaseMods(why) {
    down := ModsDown()
    if !down.Length
        return
    names := ""
    for k in down
        names .= k " "
    ; vkE8 是一个未分配的虚拟键，夹在中间让 Windows 认为 Win 键「和别的键组合过」，
    ; 否则单独一个 Win↑ 会弹出开始菜单。
    Send("{Blind}{vkE8}")
    for k in down
        Send("{" k " up}")
    fg := ""
    try fg := WinGetProcessName("A")
    LogEvent("修饰键卡住，已松开：" Trim(names) "（" why "，前台 " fg "）")
}

StuckCheck() {
    global STUCK_IDLE_MS
    if A_IsSuspended               ; 游戏期间什么都不碰
        return
    if (A_TimeIdlePhysical < STUCK_IDLE_MS)
        return
    ReleaseMods("看门狗：" STUCK_IDLE_MS // 1000 " 秒无物理输入")
}

; ===== fn 误触去抖 =====
; 只在 ACTIVE 为真时挂钩，键盘断开就自动失效，和其他映射一致。
InstallDebounce() {
    global DEBOUNCE_KEYS
    ; 用具名函数而不是 (*) => ACTIVE ——
    ; lambda 在函数作用域里，ACTIVE 未声明 global 会被当成局部变量（未赋值=假），
    ; 这组热键就永远不会触发。
    HotIf DebounceOn
    for k in StrSplit(DEBOUNCE_KEYS) {
        ; * = 不管修饰键状态都触发（Ctrl+C 也要能去抖）
        ; $ = 用钩子实现，避免自己 Send 出去的按键又触发自己
        Hotkey("*$" k, DebounceDown)
        Hotkey("*$" k " up", DebounceUp)
    }
    HotIf                      ; 恢复默认上下文
}

DebounceDown(name) {
    global DEBOUNCE_MS, REPEAT_PERIOD_MS, DB_LAST, DB_HELD, DB_REPEAT, DB_SENT, DB_SUSPECT, HOOK_TICK
    k := SubStr(name, 3, 1)
    now := A_TickCount
    HOOK_TICK := now               ; 钩子存活的证据，见「键盘钩子存活检测」
    gap := DB_LAST.Has(k) ? now - DB_LAST[k] : 999999

    if (DB_HELD.Get(k, false)) {
        ; --- 键还按着，又来一个按下 ---
        ; 不能按时间点判。实测机理是：松开 fn 的瞬间，键盘把仍按着的字母
        ; 重新发一次按下。它距首次按下多久，完全取决于 fn 被握了多久 ——
        ; 可能 50ms 也可能 800ms，和自动重复的延迟区间必然重叠。
        ;
        ; 真正稳定的区别是【周期性】：
        ;   系统自动重复 = 连续的一串，每 33ms 一个
        ;   fn 松开重复   = 孤立的一个，后面没有了
        ; 所以一律先吞掉第一个可疑的，若紧接着又来（说明是自动重复），
        ; 就转为全部放行。代价是自动重复会少掉第一个字符，几乎感知不到。
        if (DB_REPEAT.Get(k, false)) {
            Send("{Blind}{" k " Down}")        ; 已确认是自动重复，后续全放行
            DB_LAST[k] := now
            return
        }
        if (DB_SUSPECT.Get(k, 0) && now - DB_SUSPECT[k] <= REPEAT_PERIOD_MS) {
            DB_REPEAT[k] := true               ; 紧接着又来一个 = 成串 = 自动重复
            Send("{Blind}{" k " Down}")
            DB_LAST[k] := now
            return
        }
        DB_SUSPECT[k] := now                   ; 第一个可疑的，先吞掉再看
        AutoFix(k)
        return
    }

    ; --- 全新的一次按下 ---
    DB_HELD[k] := true
    DB_REPEAT[k] := false
    DB_SUSPECT[k] := 0
    if (gap < DEBOUNCE_MS) {                   ; 兜底：万一出现 down-up-down 形态的重复
        DB_SENT[k] := false
        return
    }
    DB_SENT[k] := true
    DB_LAST[k] := now
    Send("{Blind}{" k " Down}")
}

; 检测到 fn 误触后的补救。不弹任何提示，只在托盘图标提示里累计次数。
; 函数名不能叫 Recover —— AHK 不区分大小写，会和配置项 RECOVER 撞名。
AutoFix(k) {
    global RECOVER, RECOVER_KEYS, RECOVER_SKIP, DB_SENT, DB_FIXED
    if (!RECOVER || !InStr(RECOVER_KEYS, k))
        return

    ; 资源管理器这类地方 Ctrl+Z 撤销的是文件操作，不是打字，绝不能动
    try {
        proc := WinGetProcessName("A")
        if (proc && InStr(RECOVER_SKIP, proc))
            return
    } catch
        return                     ; 拿不到前台窗口就别冒险

    ; 此刻我们发出去的那次「按下」还没配对的「抬起」，先收掉，
    ; 否则后面的 Ctrl 组合会在「该键仍按着」的状态下发出，行为不可控。
    Send("{Blind}{" k " Up}")
    DB_SENT[k] := false            ; 物理抬起到来时不要再发一次

    ; 中文输入法下那个误打的字母进的是【拼音缓冲区】，不是文档。
    ; 文档没变，Ctrl+Z 撤销不了它，而且还可能被输入法自己吃掉。
    ; 这种情况要先取消组字。
    if (ImeNative()) {
        Send("{Esc}")              ; 取消输入法里那半截拼音
        Sleep(30)
    } else {
        Send("^z")                 ; 英文状态：字符已进文档，撤销它
        Sleep(40)                  ; 给应用时间完成撤销，否则两个组合会挤在一起
    }
    Send("^" k)                    ; 补发本来想要的 Ctrl+该键

    DB_FIXED += 1
    UpdateTray()
}

; 当前焦点控件的输入法是否处于中文（native）状态。
; 是的话，刚才那个误打的字母在拼音缓冲区里，不在文档里。
ImeNative() {
    focus := FocusHwnd()
    if (!focus)
        return false

    hIMC := DllCall("imm32\ImmGetContext", "ptr", focus, "ptr")
    if (!hIMC)
        return false
    conv := 0, sent := 0
    ok := DllCall("imm32\ImmGetConversionStatus", "ptr", hIMC
                , "uint*", &conv, "uint*", &sent, "int")
    DllCall("imm32\ImmReleaseContext", "ptr", focus, "ptr", hIMC)
    return ok && (conv & 1)        ; IME_CMODE_NATIVE
}

DebounceUp(name) {
    global DB_HELD, DB_REPEAT, DB_SENT, DB_SUSPECT
    k := SubStr(name, 3, 1)
    DB_HELD[k] := false
    DB_REPEAT[k] := false
    DB_SUSPECT[k] := 0
    ; 固件重复是「两次按下、一次抬起」，被吞的是第二次按下，
    ; 所以这一次抬起正好和放行的那次按下配对，必须发出去。
    ; 只有连按下都被吞掉时（上面的兜底分支）才不发，避免出现孤立的抬起。
    if (!DB_SENT.Get(k, true))
        return
    Send("{Blind}{" k " Up}")
}

; ===== 有线连接检测 =====
; USB 设备拔掉就从「在场」列表里消失，所以 cfgmgr32 的 FILTER_PRESENT 对有线完全有效。
; 注意这和蓝牙的情况正好相反 —— 已配对的经典蓝牙 HID 是常驻设备节点，
; 断电四分钟 IsPresent 依然恒为 True，那条路走不通（详见 README）。
; 同一个 API，对两种传输的可靠性截然不同。
UsbPresent() {
    global KB_USB
    static FLAGS := 0x1 | 0x100        ; FILTER_ENUMERATOR | FILTER_PRESENT
    size := 0
    if (DllCall("cfgmgr32\CM_Get_Device_ID_List_SizeW", "uint*", &size
              , "wstr", "HID", "uint", FLAGS, "uint") != 0 || size = 0)
        return false
    buf := Buffer(size * 2, 0)
    if (DllCall("cfgmgr32\CM_Get_Device_ID_ListW", "wstr", "HID"
              , "ptr", buf, "uint", size, "uint", FLAGS, "uint") != 0)
        return false
    off := 0
    while (off < size * 2) {
        id := StrGet(buf.Ptr + off, "UTF-16")
        if (id = "")
            break
        ; 必须不区分大小写：系统返回的是小写 vid_05ac 和 Col01，
        ; 和文档里的大写写法不一致。
        if (InStr(id, KB_USB, false) = 1)
            return true
        off += (StrLen(id) + 1) * 2
    }
    return false
}

; ===== 蓝牙连接检测 =====
; 唯一可靠的信号。设备节点那套（CM_Get_Device_ID_List / DEVPKEY_Device_IsPresent）
; 对经典蓝牙 HID 完全无效，实测键盘断电四分钟纹丝不动。
; 返回 1=已连接 0=未连接 -1=查询失败
BtConnected(addr) {
    static SZ_SP := 40, SZ_DI := 560
    sp := Buffer(SZ_SP, 0)
    NumPut("int",   SZ_SP, sp,  0)   ; dwSize
    NumPut("int",   1,     sp,  4)   ; fReturnAuthenticated
    NumPut("int",   1,     sp,  8)   ; fReturnRemembered
    NumPut("int",   0,     sp, 12)   ; fReturnUnknown
    NumPut("int",   1,     sp, 16)   ; fReturnConnected
    NumPut("int",   0,     sp, 20)   ; fIssueInquiry ← 0=只读本地缓存，不发起空中查询
    NumPut("uchar", 0,     sp, 24)   ; cTimeoutMultiplier
    NumPut("ptr",   0,     sp, 32)   ; hRadio = NULL（枚举所有适配器）

    di := Buffer(SZ_DI, 0)
    NumPut("uint", SZ_DI, di, 0)

    h := DllCall("bthprops.cpl\BluetoothFindFirstDevice", "ptr", sp, "ptr", di, "ptr")
    if (!h)
        return -1

    res := 0
    loop {
        if (NumGet(di, 8, "uint64") = addr) {
            ; fConnected 在偏移 20。注意 Windows 返回的是非规范化 BOOL
            ; （实测为 32 而非 1），只能判非零，不能拿 = 1 比。
            res := NumGet(di, 20, "int") ? 1 : 0
            break
        }
        di := Buffer(SZ_DI, 0)
        NumPut("uint", SZ_DI, di, 0)
    } until !DllCall("bthprops.cpl\BluetoothFindNextDevice", "ptr", h, "ptr", di, "int")

    DllCall("bthprops.cpl\BluetoothFindDeviceClose", "ptr", h)
    return res
}

; ===== 托盘 =====
BuildTray() {
    m := A_TrayMenu
    m.Delete()
    m.Add("自动（跟随蓝牙连接）", SetMode.Bind("auto"))
    m.Add("强制开启",             SetMode.Bind("on"))
    m.Add("强制关闭",             SetMode.Bind("off"))
    m.Add()
    m.Add("状态…",    ShowStatus)
    m.Add("通知提示", ToggleNotify)
    m.Add()
    m.Add("按键历史", (*) => KeyHistory())
    m.Add("事件日志", OpenEventLog)
    m.Add()
    m.Add("重新加载", (*) => Reload())
    m.Add("退出",     (*) => ExitApp())
    m.Default := "状态…"
}

; 不能写成菜单里的 lambda —— lambda 里的 EVENT_LOG 会被当成未赋值的局部变量
OpenEventLog(*) {
    global EVENT_LOG
    Run('notepad.exe "' EVENT_LOG '"')
}

SetMode(newMode, *) {
    global MODE
    MODE := newMode
    Refresh()
    UpdateTray()
}

ToggleNotify(*) {
    global NOTIFY
    NOTIFY := !NOTIFY
    UpdateTray()
}

UpdateTray() {
    global MODE, ACTIVE, NOTIFY, DB_FIXED, GAME_ON
    m := A_TrayMenu
    for name in ["自动（跟随蓝牙连接）", "强制开启", "强制关闭"]
        m.Uncheck(name)
    m.Check(MODE = "auto" ? "自动（跟随蓝牙连接）"
          : MODE = "on"   ? "强制开启" : "强制关闭")
    (NOTIFY ? m.Check("通知提示") : m.Uncheck("通知提示"))

    TraySetIcon(A_AhkPath, ACTIVE ? 1 : 3)
    A_IconTip := "Magic Keyboard Alt/Win`n"
               . "映射：" (ACTIVE ? "生效中" : "未生效")
               . "　模式：" MODE
               . (GAME_ON != "" ? "`n" GAME_ON " 运行中，脚本已暂停" : "")
               . (DB_FIXED ? "`nfn 误触已自动修正：" DB_FIXED " 次" : "")
}

ShowStatus(*) {
    global MODE, ACTIVE, KB_ADDR, KB_USB
    usb := UsbPresent()
    c   := BtConnected(KB_ADDR)
    link := usb        ? "有线 USB"
          : (c = 1)    ? "蓝牙"
          : (c = 0)    ? "未连接"
                       : "蓝牙查询失败"
    MsgBox(
        "模式：`t" MODE "`n"
      . "映射：`t" (ACTIVE ? "生效中" : "未生效") "`n"
      . "连接：`t" link "`n`n"
      . "有线 (VID_05AC&PID_0320)：`t" (usb ? "在场" : "不在场") "`n"
      . "蓝牙 (" Format("{:012X}", KB_ADDR) ")：`t"
          . (c = 1 ? "已连接" : c = 0 ? "未连接" : "查询失败") "`n`n"
      . "管理员：`t" (A_IsAdmin ? "是" : "否")
        , "Magic Keyboard Alt/Win", "Iconi")
}

; ===== 亮度控制 =====
; Windows 没有亮度快捷键，只能走 WMI。本机内置屏支持 0~100 共 101 档。
; 注意：只对笔记本内置屏有效，外接显示器需要 DDC/CI，不在此列。
Brightness(delta) {
    static wmi := ""
    t0 := A_TickCount
    try {
        if (wmi = "")
            wmi := ComObjGet("winmgmts:\\.\root\WMI")
        cur := 0
        for b in wmi.ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
            cur := b.CurrentBrightness
        val := Max(0, Min(100, cur + delta))
        for m in wmi.ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
            m.WmiSetBrightness(1, val)
        Osd("亮度  " val "%", val)
    } catch as e {
        wmi := ""                      ; 失效了就丢掉缓存，下次重建
        Osd("亮度调节失败")
    }
    if ((dt := A_TickCount - t0) >= 100)
        LogEvent("亮度调节耗时 " dt "ms")
}

; ===== 屏幕提示 =====
; WMI 改亮度不会触发系统 OSD，自己画一个，否则完全没有反馈。
; 样式：浅色底、圆角、整窗半透明。
; pct >= 0 时额外画一条进度条（亮度、音量这类有量级的反馈）。
OSD_BG     := "F5F7FB"     ; 浅底
OSD_ACCENT := "2F6FED"     ; 进度条颜色
OSD_ALPHA  := 236          ; 整窗不透明度 0-255

Osd(text, pct := -1) {
    global OSD_BG, OSD_ALPHA, OSD_ACCENT
    static g := "", txt := "", bar := "", barBg := ""
    static W := 260, H := 92

    if (g = "") {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")   ; E0x20 = 点击穿透
        g.MarginX := 0, g.MarginY := 0
        g.BackColor := OSD_BG
        g.SetFont("s12 c1B1F26 w600", "Segoe UI")
        txt := g.Add("Text", Format("x0 y26 w{} h26 Center BackgroundTrans", W), "")
        ; 轨道用一条深色 Progress 冒充，前景另起一条
        barBg := g.Add("Progress", Format("x28 y62 w{} h4 BackgroundDCE2EC", W - 56))
        bar   := g.Add("Progress", Format("x28 y62 w{} h4 Background" OSD_ACCENT, W - 56))
    }

    txt.Text := text
    if (pct >= 0) {
        barBg.Visible := true
        bar.Visible := true
        bar.Move(, , Round((W - 56) * pct / 100))
    } else {
        barBg.Visible := false
        bar.Visible := false
    }

    ; Show 的 x/y 是物理像素，w/h 是逻辑单位，算居中要换算
    scale := A_ScreenDPI / 96
    g.Show(Format("NoActivate x{} y{} w{} h{}"
                , Round((A_ScreenWidth - W * scale) / 2)
                , Round(A_ScreenHeight - 200 * scale), W, H))
    GlassRounded(g.Hwnd, 2)
    WinSetTransparent(OSD_ALPHA, g.Hwnd)
    SetTimer(() => g.Hide(), -1200)
}

; ===== 手动急停 =====
; Ctrl+Alt+F12：在 强制关闭 / 自动 之间切换，用于映射把自己绕晕时救场
^!F12:: {
    global MODE
    SetMode(MODE = "off" ? "auto" : "off")
}
