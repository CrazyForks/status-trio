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
- 本机工具链：Swift 6.4、Xcode 27.0、macOS SDK 27.0；高于仓库 CI 目标（Swift 6.3.3、Xcode 26.6、macos-26）。尚未在 CI 工具链上验证。

## DDC/CI 分流结论

没有 BenQ 实机观察，故**DDC/CI 的可行性与 `VCP 0x62` 均未验证**，不满足第二阶段门槛。本次仅修复 CoreAudio 模拟覆盖；不据此声称已解决该显示器的实际音量控制问题，也不添加 DDC 代码。
