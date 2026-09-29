# 外接显示器音量验证记录（2026-09-29）

## BenQ 实机复现矩阵

目前**未收到实机结果**。以下项目均未在 BenQ 显示器上验证，不能据此判定 CoreAudio、事件监听或 DDC/CI 是实际根因。

| 项目 | 观察结果 |
| --- | --- |
| 显示器型号 | 未提供 |
| 连接方式（直连 / 扩展坞 / 其他） | 未提供 |
| macOS 版本 | 未提供 |
| macOS「系统设置 → 声音 → 输出」音量滑杆能否操作 | 未收到实机结果 |
| Status Trio 滑杆调整后实际声音是否改变 | 未收到实机结果 |
| Status Trio 手动刷新后的读数 | 未收到实机结果 |
| 退出 Display Pilot 2 后键盘音量键的表现 | 未收到实机结果 |
| 显示器 OSD 调整后的读数 | 未收到实机结果 |

## 第一阶段模拟验证

自动化测试覆盖了 CoreAudio 输出通道枚举、仅第 3/4 通道提供音量属性、多通道合法值平均、Main 通道优先、NaN / 无穷大 / 越界值过滤、缺少音量属性时保留设备名称、动态监听注册、回调刷新、设备切换、恢复、重试、监听去重，以及同一设备 ID 通道配置缩小时清理旧监听。

- 日期：2026-09-29
- `swift test --filter CoreAudioOutputChannelElementsTests`：2 项通过。
- `swift test --filter VolumeMonitorTests`：42 项通过。
- `swift test`：通过，387 项测试、64 个 suite，0 失败。
- `swift build -c release`：通过，退出码 0。
- 本机工具链：Swift 6.4、Xcode 27.0、macOS SDK 27.0。
- CI 非发布预检：[release.yml run 36519010623](https://github.com/lingyired/status-trio/actions/runs/36519010623) 通过，head SHA `14ae1ba6724dcdaf88046f2651e258dfabf3a247`；使用 macos-26、Xcode 26.6、Swift 6.3.3，版本 1.3.4 build 17，`publish=false`，构建成功且未发布。

## DDC/CI 分流结论

原 BenQ 报告没有实机观察，故**该 BenQ 的 DDC/CI 可行性与 `VCP 0x62` 均未验证**。本 PR 仅修复 CoreAudio 覆盖；不据此声称已解决原报告，也不添加 DDC 代码。

## 2026-09-29 后续实机诊断：XV272U

用户在开发版中选择本机外接 XV272U 后，看到音量为「—」、滑杆无法控制；macOS 系统音量滑杆也不可用，但键盘音量键能改变实际声音。此设备与原报告中的 BenQ 尚未确认是同一型号，不能把以下结果推广到 BenQ。

- `system_profiler` 显示 XV272U 是当前默认 HDMI 音频输出，制造商代码 `ACR`，有两个输出通道；同名外接显示器在线。
- 对当前 CoreAudio 设备逐个检查输出 `Main` 和通道 1–8：`kAudioDevicePropertyVolumeScalar` 与 `kAudioDevicePropertyMute` 全部不存在，也不可写。Status Trio 的 `scalar == nil` 因而符合设备能力，并非多通道监听修复失效。
- 本机 BetterDisplay 4.3.4 正在运行。其 CLI 对 XV272U 的 DDC/CI `audioSpeakerVolume` (`VCP 0x62`) 读出 `100/100`，写入 `95` 后读回 `95/100`，再写回并读到 `100/100`。
- 在 `/tmp` 编译的 MIT 许可 `AppleSiliconDDC` 示例 CLI 独立于 BetterDisplay 读取 `0x62`，得到最大值 100、当前值 100；写入 95 后读回当前值 95，再恢复到 100 并读回 100。该工具的输出将此面板响应标为 `Non-interpretable by this tool`，但实际 VCP 低字节读写与 BetterDisplay 一致。

**结论：**XV272U 的可调音量位于显示器 DDC/CI 硬件层，CoreAudio 不暴露该属性。已验证本机可独立读写 `VCP 0x62`，但 Status Trio 尚未实现显示器匹配和 DDC 后端；键盘操作很可能由正在运行的 BetterDisplay 处理，尚未通过退出该应用作排他验证。保持原 PR 的 CoreAudio 修复范围；DDC 支持需要单独设计与测试。
