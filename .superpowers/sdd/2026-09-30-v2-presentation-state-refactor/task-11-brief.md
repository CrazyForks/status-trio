### Task 11：面板 ViewModel 和全部 SwiftUI 消费者接入

**Files:** Create `Presentation/Panel/StatusPanelViewModel.swift`；Modify `UI/StatusPopoverView.swift`、`StatusBarController.swift`；Modify `BatteryStatusView.swift`、`NetworkStatusView.swift`、`WiFiStatusView.swift`、`EthernetStatusView.swift`、`VPNStatusView.swift`、`BluetoothStatusView.swift`、`BluetoothDeviceList.swift`、`BluetoothDeviceRow.swift`、`NearbyBluetoothBatteryList.swift`、`NearbyBluetoothBatteryRows.swift`、`VolumeControlsView.swift`、`VolumeOutputSummaryView.swift`、`OutputDeviceList.swift`、`AudioInputControlsView.swift`、`BatteryDetailsView.swift`、`WiFiNetworkListView.swift`、`EthernetLinkView.swift`；审计并迁移仍解释领域模型的 `WiFiStatusIcon.swift`、`BluetoothDeviceRowIcon.swift`、`AudioOutputDeviceIconView.swift`，更新 `BluetoothListeningModeControl.swift` 的文案输入（需要时）；Create `Tests/StatusTrioCoreTests/StatusPanelViewModelTests.swift`、`PanelPresentationWiringTests.swift`；Modify 这些 views 的现有布局、scroll、permission、popover tests。

**Interfaces:** `@MainActor StatusPanelViewModel: ObservableObject` initializer 为 `(store: SystemStatusStore, settings: SettingsStore, localization: Localization, actions: StatusPanelActions)`；公开 private(set) published `battery: PanelSummaryState`、`network: PanelSummaryState`、`vpn: PanelSummaryState`、`bluetooth: BluetoothPanelState`、`volume: VolumePanelState`、`audioInput: AudioInputPanelState`、三种 detail 状态。`start()`／`stop()` 只负责展示订阅，不启动／停止领域监控。views 改为 `state:` + callbacks；Settings 的 UI 偏好可以由 ViewModel 投递，不能再让 view 解读设备领域对象。

detail 属性明确为 `batteryDetails: PanelDetailState`、`wifiDetails: WiFiPanelState`、`wiredDetails: PanelDetailState`。`PanelDetailRow.isCopyable` 携带现有 LinkDetailPresentation 的地址行资格，SwiftUI 通过显式 copy-value callback 处理点击，不在 view 重算地址策略。保留多个区域 publisher，不能对大型联合 state 每次任何变化都重新发布所有区域。

Wi-Fi details 保留 view-local More／Less toggle：用 `wifiDetails.visibleDetailRows(expanded:)` 展示完整解析行集的折叠／展开切片，并使用 state 提供的 `showMoreTitle`／`showLessTitle`；不得在 view 重映射 `WiFiConnectionDetails` 或丢弃追加的八行。

Bluetooth summary 根据 `PanelSummaryIntent.requestBluetoothAuthorization`／`.openBluetoothPermissionSettings` 路由到独立 action callbacks。普通设备行 tap 调 `rowTapped(address:)`，确认按钮调 `confirmBluetoothDisconnect(address:)`，取消调 `cancelDisconnect()`。行呈现使用 resolved connected／battery layout／segments（包括 charging case glyph）／status text and tint／confirmation fields，不在 view 检查设备类别或重算 battery policy。panel reorder 把当前实际显示的 pairedRows 地址切片（包含 collapsed limit）与 offsets／destination 传给 action；collapsed destination count 插到该可见 slice 尾端，保持其后未显示行的 saved ranks。

- [ ] 新失败测试确保按独立源更新：`popupSnapshot` 更新 battery／network；`liveVolume` 立即更新 volume；`liveInput` 更新 input；VPN 更新不触发 icon。使用既有 mock monitors／store fixtures，重用当前测试的 ManualEventSleeper，不新增固定睡眠。
- [ ] Run `swift test --filter 'StatusPanelViewModelTests|PanelPresentationWiringTests'`。按区域 Combine delivered values，`removeDuplicates` 后发布；controller 多字段如只支持 `objectWillChange`，安排主 actor coalescer 在变更落地后读一致的 controller 快照，不在 willChange 回调读旧值。
- [ ] StatusBarController 组装一个 panel owner 并给 retained popover 使用；view 对 `PopupSection` 的 switch 保留，领域引用由 state + callbacks 替代。controller 保留 popover setVisible gate；ViewModel start 不能主动扫描。旧 SwiftUI preview／test initializer 可短期 adapter，必须标记调用方并在 Task 12 清掉。
- [ ] 音量 Slider 保留局部 draft／isAdjusting：

```swift
.onChange(of: state.scalar) { _, newValue in
    guard !isAdjusting else { return }
    draftVolume = newValue ?? 0
}
```

editing begin／end 使用现有对称动作，在 end 调 `finishVolumeAdjustment`；不因 model 更新重复 setVolume。scroll target 的 bounds 注册和自然滚动设置保持；Menu Bar 滚轮仍作用同一 store 动作，通过协调入口传递。

- [ ] 迁移 output／input row select 为稳定 key，列表重排不误选；SwiftUI 本地 expansion／drag 可保留，但排序和过滤输入已由展示层解析。synthetic listening controls、preview language、设备行颜色及 busy 控制一并保持。
- [ ] lifecycle spy 测试 state 更新不触发 scan；appear／disappear 配对，关闭全部 details，返回后正确释放；语言切换能更新 retained view，图标 raster 不变。System Settings URL 次序保持，运行 `swift test --filter StatusMenuBuilderTests`。
- [ ] 全部六区／详情的布局快照、scroll targets、input capability、Bluetooth action tests 和完整门槛通过后提交：`refactor: bind status panel views to presentation state`。
