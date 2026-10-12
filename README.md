# Magic Keyboard on Windows

让 Apple Magic Keyboard 在 Windows（HONOR MagicBook DRA-XX，US 布局）上用起来
符合 PC 习惯：底排修饰键归位，F1~F12 按键帽图标的语义工作，左 Shift 单按切换中英文。

运行：

```
F:\Tools\AutoHotkey\v2\AutoHotkey64.exe "F:\Code\Temp\Keyboard\magic-kb-swap\MagicKbSwap.ahk"
```

首次使用：把 `config.example.ahk` 复制为 `config.local.ahk`，填上键盘的蓝牙 MAC（获取方法见文件内注释）。
这个文件只在本机，不进版本库。

**退出脚本即完全还原**——映射只活在进程里，不写注册表、不装驱动、不需要重启。

---

## 一、底排修饰键

```
笔记本底排      :  Ctrl    Fn    Win    Alt   [Space]
Magic KB 底排   :  fn   control  option command [Space]
```

两边的 **Fn 键都不可重映射**——被键盘固件吃掉，不产生标准 HID 事件，
任何软件都碰不到（已用 KeyProbe 实测确认：按下毫无记录）。
把两边的 fn 剔除后对齐剩下三颗：

```
笔记本          :  Ctrl   Win   Alt
Magic 原生      :  Ctrl   Alt   Win      ← 后两颗是反的
Magic + 本脚本  :  Ctrl   Win   Alt      ← 对齐 ✓
```

左右两侧对称交换。**唯一无法消除的差异**：笔记本最左下角是 Ctrl，
Magic 最左下角是 fn，三颗修饰键整体右移一位。

## 二、F1~F12

Magic Keyboard 送出的是**真正的 F1~F10**（VK 70–79 / SC 03B–044），
不是媒体键——键帽上的亮度、聚焦等图标是 macOS 驱动层翻译的，
裸 HID 就是普通功能键。所以这些键在 Windows 上默认几乎无用，正好拿来重映射。

| 键 | 键帽图标 | Windows 动作 | 实现 |
|----|---------|-------------|------|
| F1 | 🔅 亮度减 | 亮度 −10 | WMI `WmiSetBrightness` |
| F2 | 🔆 亮度加 | 亮度 +10 | 同上 |
| F3 | 调度中心 | 任务视图 | `Win+Tab` |
| F4 | 🔍 聚焦 | 不映射（前缀键暂时停用，见下节） | — |
| F5 | 🎤 听写 | 语音输入 | `Win+H` |
| F6 | 🌙 勿扰 | 通知中心 | `Win+N`（Windows 无勿扰快捷键，这是最接近的） |
| F7 | ⏮ | 上一曲 | `Media_Prev` |
| F8 | ⏯ | 播放/暂停 | `Media_Play_Pause` |
| F9 | ⏭ | 下一曲 | `Media_Next` |
| F10 | 🔇 | 静音 | `Volume_Mute` |
| F11 | 🔉 | 音量 − | `Volume_Down` |
| F12 | 🔊 | 音量 + | `Volume_Up` |

**右上角锁屏键不可见**，固件层处理，无解。

> 关于 F11/F12 的一段弯路：最初用 KeyProbe（基于 `InputHook`）探测时它们
> 没有记录，我据此判断"走消费类 HID 用途、钩子看不到"。后来用 Raw Input
> 复查，发现它们就是**标准键盘按键**（VK=7A/7B，SC=057/058）；再用真正的
> 热键测试，钩子也能正常看到。
>
> **结论：KeyProbe 有盲区，不是权威。** 判断某个键能否映射，以
> `RawProbe.ahk` 和实际热键为准。

### 代价：裸 F 键没了

映射后，**单独按** F2 不再是「重命名」、F3 不再是「查找下一个」、
F5 不再是「刷新」。而 fn 不可用，所以没有「按住 fn 取回真 F 键」这条退路。

补偿机制：脚本用的是**裸键热键**（没有 `*` 前缀），AHK 要求修饰键完全匹配，
因此 `Ctrl+F5`、`Shift+F3`、`Alt+F4` 这类组合会**原样透传**给应用。
丢失的只有不带修饰键的那一下。

不想要某个键，把 `MagicKbSwap.ahk` 里对应那行注释掉，并从 `MAP_KEYS` 里删掉即可。

## 三、前缀键（Leader Key）——暂时停用

**当前 F4 是普通 F4。** 为保证输入体验先停用了，代码都还在：
在 `MagicKbSwap.ahk` 里取消注释 `F4::LeaderStart()`，再把 `"F4"` 加回 `MAP_KEYS` 即可恢复。

启用时：按 `F4`，再按一个键执行对应动作。没有界面；按完 F4 停顿超过 0.6 秒
还没按第二个键，才用系统原生 ToolTip 列出可用的键。3 秒无操作或按 `Esc` 取消。

| 键 | 动作 |
|----|------|
| `c` | Chrome：激活普通浏览器窗口（排除网页安装成的 PWA）并开新标签页，焦点在地址栏 |
| `t` | Windows Terminal 新标签，PowerShell 7，起始目录 `F:\Code\Temp` |
| `v` | VS Code：已开就激活，否则启动 |

加功能只改 `Actions.ahk`，在数组里加一条：

```ahk
{ key:   "t"
, label: "终端"
, hint:  "Windows Terminal"
, run:   () => Run("wt.exe") },
```

框架 `lib\Leader.ahk` 不用动。更多构想见 `IDEAS.md`。

## 四、左 Shift 单按切换中英文

微软拼音自己的「单按 Shift 切换」偶尔会漏。现在由脚本接管左 Shift：

1. 左 Shift 按下时，脚本补发一个未分配的虚拟键 `vkE8`。输入法看到 Shift 和别的键组合过，就不会自己再切。
2. 左 Shift 松开时，如果这期间没按过别的键、也没按着 Ctrl/Alt/Win，脚本通过输入法默认窗口发
   `WM_IME_CONTROL` 直接切换（`SendMessageTimeout`，最多等 100ms）。

- Shift 本身照常传给系统（`~` 前缀），Shift+字母、Ctrl+Shift+T 这些组合不受影响。
- 按住多久都算单按，和原生行为一致（实测原生按住 800ms 也会切）。
- 微软拼音的中文模式值是 `1025`（NATIVE|SYMBOL），英文是 `0`。从中文切英文时只清掉 NATIVE 位（写成 `1024`）会被忽略，必须整值写入 `0`。
- 如果主线程忙，补发 `vkE8` 时 Shift 已经松开，就赶不上了。这时脚本不再切换，交给输入法自己切，避免两次抵消。
- 右 Shift 不归脚本管，保持输入法原生行为。这个功能和键盘连接状态无关，内置键盘同样生效。

## 五、三种模式（托盘菜单）

- **自动**（默认）：键盘有线插着或蓝牙连上 → 映射生效；断开 → 自动还原（延迟 ≤2 秒）
- **强制开启** / **强制关闭**：手动锁定，不理会连接状态

`Ctrl+Alt+F12` 在「强制关闭」和「自动」之间切换，用于映射把自己绕晕时救场。

## 六、稳定性与自我保护

### 热键一律不带 `#HotIf` 条件（键盘钩子频繁失效的根因）

旧版用 `#HotIf IsActive()` 控制映射开关。症状是：输入时不时卡顿，
隔一段时间映射整体失效，按键历史显示 `Keybd hook: no`，重启脚本才恢复。

机理见 AutoHotkey 文档 `#HotIfTimeout` 一节：

- 带条件的热键，每次按键都要从钩子线程回到**主线程**求值条件，主线程忙时钩子就跟着等（AHK 最多等 1000ms）。
- Windows 给低级钩子的时限默认只有 **300ms**（`LowLevelHooksTimeout`）。超时 10 次以内放过，**第 11 次直接把钩子摘掉**，不通知。

实测证据：

- 事件日志里记到「主线程卡顿 447ms」，两秒后就检测到钩子失效。
- 把主线程冻结 3 秒、期间注入 15 个字母做对照：

| | 每个字母的延迟 | 15 个字母实际到达 |
|---|---|---|
| 旧版（带条件） | 600~800ms | 6 个 |
| 新版（无条件） | ≤16ms | 15 个 |

现在所有热键都不带条件，映射开关由 `SetMapping()` 用 `Hotkey(名字, "On"/"Off")` 整组切换。
拦不拦由钩子线程自己决定，主线程卡多久都不影响按键。

**以后加热键也不要用 `#HotIf`**，并把热键名加进 `MAP_KEYS`。注意重映射 `X::Y` 在 AHK 里的名字是 `*X` 和 `*X up`。

### 钩子存活检测（安全网）

- **两个独立通道比对。** Raw Input 和低级钩子是两条互不依赖的输入通道，钩子没了 Raw Input 照样收得到。
  钩子这一侧用一个只观察、不拦截的 `InputHook("V I0 L0")` 记录按下时刻。
- **判定与处理。** 如果 Raw Input 看到了按键，而钩子一侧 1 秒内没有跟上，就判定钩子已死：写日志，然后 `Reload()`。
- **防死循环。** 60 秒内重启过一次仍不恢复，就停止检测，日志记「需手动处理」。时间戳写在 `.hook-reload`。
- **不算失效的情况。** 前台是管理员窗口（UIPI 下钩子本来就看不到按键），或者脚本因游戏而暂停时，都不算。

### 主线程卡顿记录

- 每 100ms 一次的计时器，间隔超出 250ms 就记一条「主线程卡顿」，附带前台程序和物理空闲时长。超过 30 秒的间隔视为睡眠，不记。
- 设备检测 `Refresh` 或亮度调节超过 100ms 时，单独记录耗时。

### 修饰键卡住防护

症状：command 和 option 都变成 Win。本质是系统里的 LWin 一直处于「按下」——
锁屏、UAC、睡眠、USB 瞬断时，钩子看不到修饰键的松开。两道防线：

1. 解锁、唤醒时主动松开被映射的修饰键（先补一个 `vkE8`，防止单独的 Win↑ 弹出开始菜单）。
2. 看门狗：系统认为修饰键按着，但物理键盘已经 3 秒没有任何输入，就判定为卡住，自动松开。真按着的键会持续自动重复，不会这么久没有事件。

### 游戏让路

`YuanShen.exe` / `GenshinImpact.exe` 运行期间，脚本整体 `Suspend`。同时撤掉观察用的 InputHook，
键盘钩子被完全卸掉，对反作弊不可见。游戏退出后自动恢复。
这期间左 Shift 也回到输入法原生行为。

原因：原神反作弊会干预键盘输入，和钩子同时存在时出现过 Win 键卡住；它还会拦截注入的按键。

### 事件日志

`events.log`，托盘「事件日志」可打开。只记事件，不记按键内容：

- 启动、映射开关
- 锁屏/解锁、睡眠/唤醒
- 修饰键卡住、钩子失效、主线程卡顿
- 游戏启停

超过 512KB 轮换成 `.old`。托盘「按键历史」显示最近 500 个按键事件，含 `Keybd hook: yes/no`。

## 已移除：fn 误触去抖

曾经针对「松开 fn 时键盘把仍按着的字母重发一次」做过去抖和自动撤销补救。
现在习惯上已不再误按 fn，而且它让左手区 15 个字母全部变成带条件的热键，是钩子超时的最大来源，所以移除了。
带去抖的完整版本和机理说明保留在 `archive\MagicKbSwap.with-debounce.ahk`。

---

## 两种连接方式的检测

同一把键盘，蓝牙和有线在 Windows 眼里是**两个完全不同的设备**：

| 连接 | VID | PID | 检测方式 |
|------|-----|-----|---------|
| 蓝牙 | `0x004C`（Apple 的 Bluetooth SIG 厂商号） | `0x0320` | `BluetoothFindFirstDevice` 的 `fConnected` |
| 有线 | `0x05AC`（Apple 的 USB 厂商号） | `0x0320` | cfgmgr32 查 HID 设备是否在场 |

有线时的设备节点：

```
HID\VID_05AC&PID_0320&MI_01&Col01\...     键盘集合
USB\VID_05AC&PID_0320\<序列号>          USB 设备
```

**判断顺序不能反：有线必须优先。** 插线后键盘会断开蓝牙，此时 `BtConnected`
必然返回 0；若先查蓝牙就会把有线状态误判成「未连接」。实测：

```
UsbPresent()  -> HID\VID_05AC&PID_0320&MI_01&Col01\...
BtConnected() -> 0
```

**有讽刺意味的一点**：cfgmgr32 的 `FILTER_PRESENT` 对有线完全可靠（拔掉即消失），
而这正是本项目最初对蓝牙用过、又被实测推翻的那个方案。同一个 API，
对两种传输的可靠性截然相反——经典蓝牙 HID 配对后是常驻设备节点，
断电四分钟 `IsPresent` 依然恒为 True。

### 有线与蓝牙的行为差异：没有

HID 描述符结构确实不同，但**对使用者没有任何影响**：

| | 蓝牙 | 有线 |
|---|---|---|
| Col01 键盘集合 | 5 个输入字段 | **6 个**（多了 Eject `0x0C/0xB8`、Menu `0x0C/0x40`） |
| fn | `0xFF00/0x0003` | `0x00FF/0x0003` |
| 锁屏键 | `0x0C/0x019E` | `0x0C/0x019E` |
| Col02 | vendor `0xFF00/0x0014` | **真正的消费类集合** `0x0C/0x0001` |
| Col03 | 无 | vendor `0xFF00/0x0006`，65 字节报告 |

**fn 和锁屏键在两种连接下都完全不可见。** 它们始终嵌在键盘顶层集合内部，
Windows 把该集合翻译成键盘事件时丢掉了 vendor 位，用户态够不着。
有线多出来的 Col02/Col03 是媒体键和 vendor 配置通道，不承载 fn。

实测（`RawProbe.ahk`，有线连接）：同一次会话捕获到 34 个事件，字母、
媒体键、修饰键全部正常，**按 fn 和锁屏键零事件**。探测器本身可用，
所以这个零结果是有效证据。

另有一个未深究的观察：`USB\VID_05AC&PID_0320&MI_00` 接口状态是 `Error`。

## 开机自启

启动文件夹快捷方式，不写注册表、不需要管理员：

```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\MagicKbSwap.lnk
  → F:\Tools\AutoHotkey\v2\AutoHotkey64.exe "F:\Code\Temp\Keyboard\magic-kb-swap\MagicKbSwap.ahk"
```

删掉快捷方式即取消。

**代价**：这样启动没有管理员权限，映射对提权窗口（任务管理器、管理员终端）
无效——这是 Windows 的 UIPI 限制。需要覆盖提权窗口就得改用计划任务并勾选
「使用最高权限运行」。

## 为什么蓝牙必须轮询 API

本项目最深的坑。

**设备节点信号全部无效。** 最直觉的做法是检测 HID 设备在不在场
（`CM_Get_Device_ID_ListW` + `CM_GETIDLIST_FILTER_PRESENT`，或
`DEVPKEY_Device_IsPresent`）。实测把键盘**物理断电 4 分钟**，纹丝不动：

```
time     | cfgmgrPresent | hidNode | bthenumIsPresent | btApiConnected
17:44:19 | True          | OK/True | True             | CONNECTED     ← 断电前
17:44:26 | True          | OK/True | True             | disconnected  ← 断电
  ...     （4 分钟全程）                                disconnected
17:48:39 | True          | OK/True | True             | disconnected
17:48:45 | True          | OK/True | True             | CONNECTED     ← 上电
```

Windows 把已配对的经典蓝牙 HID 当作常驻设备节点，电源状态完全不影响它。
连带后果：

- **Windows 设置里永远显示「已连接」**，因为
  `DEVPKEY_DeviceContainer_AlwaysShowDeviceAsConnected = True`。这是故意的——
  键盘平时休眠、按键才唤醒，如实显示会导致界面反复闪断。
- **设置里没有「断开连接」按钮**，只有「删除设备」
  （`DEVPKEY_DeviceContainer_UnpairUninstall = True`）。
- **`WM_DEVICECHANGE` 用不了**。节点从不变化就不产生变更事件，
  所以只能轮询，没有事件驱动这条路。

**唯一可靠的是 `BluetoothFindFirstDevice` 的 `fConnected`。**
断电 ≤7 秒、重连约 6 秒即可察觉。单次调用实测 2.5ms，2 秒轮询开销可忽略。

`fIssueInquiry = FALSE` 是关键：只读本地缓存，不发起空中查询，
否则每次轮询都扫描射频，既慢又耗电。

### 结构体偏移（x64）

```
BLUETOOTH_DEVICE_SEARCH_PARAMS  sizeof = 40
BLUETOOTH_DEVICE_INFO           sizeof = 560
  dwSize          0
  Address         8    (ULONGLONG，注意 4→8 有对齐填充)
  ulClassofDevice 16
  fConnected      20
  fRemembered     24
  fAuthenticated  28
  stLastSeen      32   (SYSTEMTIME, 16)
  stLastUsed      48   (SYSTEMTIME, 16)
  szName          64   (WCHAR[248])
```

已用 C# `Marshal.OffsetOf` 交叉验证。

**`fConnected` 是非规范化 BOOL**：实测返回 `32` 而不是 `1`。必须判非零，
写成 `== 1` 会永远为假。

---

## 已知限制

- **不加管理员权限时，映射对提权窗口无效**（任务管理器、管理员终端等）。
  这是 Windows 的 UIPI 限制。需要的话用管理员身份启动脚本。
- 映射是全局的，笔记本内置键盘同样受影响（包括 F1~F12）。当前需求下可接受。
- 亮度调节**只对笔记本内置屏有效**，外接显示器需要 DDC/CI，未实现。
- 假定 US 布局（已确认 `00000409`）。ISO 布局的 `RAlt` 可能承担 AltGr。
- 蓝牙 MAC 要在 `config.local.ahk` 里配置 `KB_ADDR`，否则只能检测有线连接。

## 踩坑记录

- **Bash 工具会折叠反斜杠**。用 heredoc 写 `"winmgmts:\\.\root\WMI"`，
  落到文件里变成 `"winmgmts:\.\root\WMI"`，WMI 报 `0x80041021`。
  这一度让人误判成 AHK 的 moniker 不支持 `\\.\` 形式——实际该形式完全正常。
  **写含反斜杠的内容用 Write 工具或 Python，别用 bash heredoc。**
- **Git Bash 吞掉命令行开关**。`/validate`、`/ErrorStdOut` 被 MSYS 当成 Unix
  路径翻译（变成 `D:/Applications/Git/ErrorStdOut`），AHK 报
  "Script file not found" 并弹模态框卡住。用 PowerShell 调用，或设
  `MSYS2_ARG_CONV_EXCL="*"`。
- **把 validate 套进 `$(powershell ...)` 会吞掉退出码**，导致假通过。
- **AHK v2 变量名不区分大小写，且与内置函数同名空间**：
  参数 `mode` 撞 `global MODE`；变量 `LOG` 撞内置函数 `Log()`。
- **HID 实例 ID 会变**：结尾 `&N&` 每次重连递增（`&2&0000` → `&3&0000`），
  且系统返回小写 `Col01` 而非文档的 `COL01`。该方案最终废弃，但坑仍成立。
- **测试其他 AHK 脚本的热键需要 `SendLevel 1`**。默认 SendLevel 0 的合成按键
  会被所有 AHK 脚本忽略，`Send("{F1}")` 什么都不会触发。更稳的做法是用 `DllCall("SendInput")`
  直接注入（`dwExtraInfo = 0`，不带 AHK 标记）。
- **`#HotIf` 条件会拖垮钩子**，见「热键一律不带 `#HotIf` 条件」。
- **`KeyHistory` 的 `Keybd hook: yes` 不一定可信**：主线程冻结测试里旧版丢了一大半按键，事后仍显示 yes。判断钩子死活以 Raw Input 比对为准。
- **AHK v2 函数里读全局变量必须 `global` 声明**，lambda 也一样，否则读到的是未赋值的局部变量。
  顶层语句按书写顺序执行，全局变量要定义在使用它们的调用之前。

## 目录内容

| 文件 | 用途 |
|------|------|
| `MagicKbSwap.ahk` | 主脚本：模式管理、连接检测、修饰键交换、F 键映射、左 Shift 切换、各项自我保护 |
| `Actions.ahk` | 前缀键动作表（前缀键暂时停用） |
| `config.example.ahk` | 本机配置模板，复制为 `config.local.ahk`（不进版本库）后填写 |
| `lib\Leader.ahk` | 前缀键框架：等键、ToolTip 提示、动作派发 |
| `lib\Glass.ahk` | 亚克力毛玻璃窗口（亮度提示等 OSD 用） |
| `events.log` | 事件日志 |
| `archive\` | 已移除功能的旧版本（fn 去抖） |
| `IDEAS.md` | 快捷键构想池 |
| `KeyProbe.ahk` | 键位探测器（基于 InputHook，**有盲区**，见上文） |
| `RawProbe.ahk` | Raw Input 探测器，读原始 HID 报文，判断按键存在性以此为准 |

## 踩过的 DPI 坑

本机 3072×1920 @ 192 DPI（200% 缩放），浮层定位踩了两层坑：

- **`Gui.Show` 的 `x`/`y` 是物理像素，`w`/`h` 是逻辑单位**（会被 AHK 按 DPI 放大）。
  拿物理的 `A_ScreenWidth` 减逻辑的宽度算居中，会偏出半个窗口。
  正确做法：`x = (A_ScreenWidth - W * A_ScreenDPI / 96) / 2`。
- **不要 `Show("Hide x.. y..")` 之后再 `Show("NoActivate")`**。
  第二次不带坐标，AHK 会按默认位置重新摆放。只在一处带坐标 Show。
- **截图工具本身也会骗人**：DPI 不感知的进程截出来的不是缩小的全屏，
  而是左上角的 1:1 裁剪。排查时先 `SetProcessDPIAware()`。

## `#Include` 的相对路径

被包含的文件里，`%A_ScriptDir%` 指向的是**主脚本**的目录，不是该文件自己的目录。
库文件互相包含要用 `%A_LineFile%\..\Xxx.ahk`（`A_LineFile` = 当前文件的真实路径），
否则换个入口脚本就找不到了。
