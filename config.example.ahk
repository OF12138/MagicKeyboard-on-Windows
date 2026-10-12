; 复制本文件为 config.local.ahk，填上自己的值。config.local.ahk 不进版本库。
;
; 蓝牙 MAC：设置 → 蓝牙和设备 → 设备 → 更多设备和打印机设置 → 键盘属性 → 硬件 →
; 属性 → 详细信息 → 「蓝牙设备地址」；或 PowerShell：
;   Get-PnpDevice -Class Bluetooth | ? FriendlyName -like '*Keyboard*' | select InstanceId
; InstanceId 末尾 12 位十六进制就是。
KB_ADDR := 0x000000000000

; 软件装在非默认位置时覆盖（默认值见 Actions.ahk）
; PATH_VSCODE := "D:\Apps\VS Code\Code.exe"
