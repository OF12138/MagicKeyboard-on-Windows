/*
 * Actions.ahk —— 前导键动作表（这是你平时要改的唯一文件）
 *
 * 加一个功能 = 在下面的数组里加一条。字段：
 *   key    第二个键（单个字符，小写）
 *   label  停顿提示里显示的名字
 *   run    一个无参函数，被选中时执行；可以在里面写一串动作
 *
 * 顺序就是提示里的显示顺序。
 */

; ===== 常用路径，集中在这里方便改 =====
PATH_CHROME := "C:\Program Files\Google\Chrome\Application\chrome.exe"
PATH_CLAUDE := EnvGet("USERPROFILE") "\.local\bin\claude.exe"
PATH_VSCODE := EnvGet("LOCALAPPDATA") "\Programs\Microsoft VS Code\Code.exe"   ; 装在别处的话在 config.local.ahk 里覆盖
DIR_CODE    := "F:\Code"
DIR_TERM    := "F:\Code\Temp"       ; F4 → t 打开终端时的起始目录
; Windows Terminal 里 PowerShell 7 的配置。默认配置是旧版 Windows PowerShell 5，所以要显式指定。
; 用 GUID 而不是名字，改配置名也不会失效。
WT_PWSH7    := "{574e775e-4f2a-5b96-ac1e-a2962a402336}"

LeaderActions() {
    return [
        { key:   "c"
        , label: "Chrome"
        , run:   () => Act_Chrome() },

        { key:   "t"
        , label: "终端 (pwsh 7)"
        , run:   () => Act_Terminal() },

        { key:   "v"
        , label: "VS Code"
        , run:   () => Act_VSCode() },

        ; ---- 以下为示例，取消注释即可启用 ----
        ; { key:   "k"
        ; , label: "Claude Code"
        ; , run:   () => Act_ClaudeCode() },
    ]
}

; ===== 动作实现 =====

; 在最近用过的 Chrome 浏览器窗口里开新标签页，光标落在地址栏，直接打字就是搜索。
; 没有浏览器窗口就开一个新窗口（新窗口本身就聚焦地址栏）。
;
; 「安装为应用」的网页（iCloud、X 等 PWA）和浏览器是同一个 chrome.exe、同一个窗口类，
; 只能靠标题区分：浏览器窗口标题固定以 " - Google Chrome" 结尾，PWA 没有。
Act_Chrome() {
    global PATH_CHROME
    for h in WinGetList("ahk_exe chrome.exe ahk_class Chrome_WidgetWin_1") {   ; 按 Z 序，最近的在前
        if RegExMatch(WinGetTitle(h), "(^| - )Google Chrome$") {
            WinActivate(h)
            if !WinWaitActive(h, , 1)
                throw Error("Chrome 窗口没能切到前台")
            Send("^t")
            return
        }
    }
    if !FileExist(PATH_CHROME)
        throw Error("找不到 Chrome：" PATH_CHROME)
    Run('"' PATH_CHROME '" --new-window')
}

; 在最近的 Windows Terminal 窗口里开一个 pwsh 7 新标签页，起始目录 DIR_TERM；
; 没有终端窗口就新开一个。-w 0 = 最近使用的窗口。
Act_Terminal() {
    global DIR_TERM, WT_PWSH7
    Run('wt.exe -w 0 nt -p "' WT_PWSH7 '" -d "' DIR_TERM '"')
}

; 已开着 → 切到最近的 VS Code 窗口；没开 → 启动。
Act_VSCode() {
    global PATH_VSCODE
    sel := "ahk_exe Code.exe ahk_class Chrome_WidgetWin_1"
    if WinExist(sel)
        return WinActivate(sel)
    if !FileExist(PATH_VSCODE)
        throw Error("找不到 VS Code：" PATH_VSCODE)
    Run('"' PATH_VSCODE '"')
}

Act_ClaudeCode() {
    global PATH_CLAUDE, DIR_CODE
    if !FileExist(PATH_CLAUDE)
        throw Error("找不到 claude.exe：" PATH_CLAUDE)
    ; 单引号用 Chr(39) 拼，省掉多层引号转义
    q := Chr(39)
    Run('wt.exe -d "' DIR_CODE '" pwsh -NoLogo -NoExit -Command "& ' q PATH_CLAUDE q '"')
}
