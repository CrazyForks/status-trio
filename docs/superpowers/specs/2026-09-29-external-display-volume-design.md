# 外接显示器音量监控设计

## 目标与事实边界

用户反馈是「切换到 BenQ 显示器音箱后，Status Trio 无法监控音量变化」。这句话尚不能证明 Status Trio 的滑杆也无法控制音量，更不能证明该设备使用 DDC/CI。目标是先修复已确认的 CoreAudio 多通道覆盖不一致，再根据真实设备证据决定是否加入显示器硬件音量支持。

当前 `CoreAudioVolumeReader` 与 `CoreAudioVolumeEventMonitor` 只检查输出 `Main/1/2`；`CoreAudioOutputController` 通过 `kAudioDevicePropertyStreamConfiguration` 枚举全部输出通道。设备列表可能读到实时监控没有读取或监听的通道。默认设备切换、事件监听恢复和静音监听也使用这条路径。

## 第一阶段：CoreAudio 覆盖一致

- 将现有输出通道枚举抽成共享的 HAL 辅助能力，供控制器与 `CoreAudioClient` 使用；保留现有三次读取重试与元数据失败时的 `[1, 2]` 兼容回退。
- 读取器先读 `Main` 音量；不存在或读失败时，对可读且有限、位于 `0...1` 的输出通道标量取算术均值，与设备列表的多通道呈现策略一致。没有有效标量时保持 `nil`，不显示虚假的 0%。
- 静音读取沿用 `Main` 优先、随后第一个可读通道的现有语义，只将搜索范围扩展到全部输出通道；不在本阶段重新定义多通道部分静音的语义。
- 事件监听器在当前输出设备真正提供属性的每个枚举元素上注册 `VolumeScalar` 和 `Mute`；只移除成功注册的监听，设备切换与恢复后重新枚举，不重复注册。
- 本阶段不改变输出设备选择、音量写入、`SystemStatusStore` 的乐观显示、菜单栏与 Dock 的渲染，也不增加后台轮询。

验收：模拟仅在第 3 通道及以后暴露音量的设备时，实时读取、事件触发刷新、设备列表读数一致；无音量属性的设备仍显示不可调；现有设备切换、监听恢复和停用测试通过。真实 BenQ 的结论须由下述诊断证据支持，不能由模拟测试推断。

## 设备诊断与分流

请报告用户在 BenQ 作为系统默认输出时分别记录：macOS「系统设置 → 声音 → 输出」音量滑杆能否拖动；Status Trio 滑杆调整后实际声音是否改变；手动刷新后数值是否改变；退出 Display Pilot 2 后，键盘音量键及显示器 OSD 调整时的表现。只记录设备型号、连接方式、macOS 版本、上述观察与可安全共享的音频属性能力，不收集设备 UID 或其他个人标识。

判定规则：系统滑杆可用且手动刷新正确、实时不更新，优先查监听；系统滑杆可用而刷新读错，优先查读取；系统音量属性不存在或不可写、但显示器 OSD/Display Pilot 可调整，转入显示器硬件音量可行性验证。若现象不同，保留原始观察并重新定位，不把 DDC 当作既定原因。

## 第二阶段：条件性 DDC/CI 支持

仅在目标型号实机证明 `VCP 0x62` 可读写，并能将当前 CoreAudio 音频端点可靠地对应到**唯一**外接显示器后，另立实施计划。届时的候选架构是 CoreAudio 优先、无可用 CoreAudio 音量时才尝试显示器后端；匹配失败或不唯一时禁用控制。DDC 没有本项目现有的 CoreAudio 属性监听，因此须另外确定面板开启时的有限读取节奏、关闭后的停止条件、设备切换与唤醒刷新，以及菜单栏/Dock 对外部 OSD 改动可接受的延迟。不能把持续后台轮询所有显示器作为默认方案。

这一阶段还需验证连接线、扩展坞、Apple Silicon、DDC/CI 开关、显示器不支持 `0x62`、读写失败和第三方控制软件并存时的行为。任何 DDC 实现都不能靠设备名称模糊匹配或在写入失败后假装成功。

参考资料：[Apple 音频设备音量属性说明](https://developer.apple.com/library/archive/qa/qa1016/_index.html)、[BenQ Display Pilot 2 音量适用条件](https://www.benq.com/en-us/support/downloads-faq/faq/product/troubleshooting/monitor-faq-kn-00029.html)、[MonitorControl 的 DDC 功能与连接限制](https://github.com/MonitorControl/MonitorControl)。这些资料说明技术可能性，不证明本次 BenQ 用户的具体根因。

## 平台与验证约束

- 最低 macOS 15；Swift 代码须兼容仓库 CI 的 `macos-26`、Xcode `26.6`、Swift `6.3.3`。
- Swift 改动提交前运行 `swift test` 与 `swift build -c release`；如果修改 actor 隔离或 `@MainActor` 边界，合并或发布前运行 `publish=false` 的 release workflow，遵守根目录 `AGENTS.md`。
- 保留本机已有的未提交文件；本设计与计划文件之外不修改工作区。
