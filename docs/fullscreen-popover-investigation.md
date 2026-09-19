# 其他 App 全屏时菜单栏面板不弹出（issue #48）

状态：**已修复，真机确认通过**。

关联 issue：[#48 其他 APP 全屏的时候，点击 menubar 无法弹出状态页](https://github.com/lingyired/status-trio/issues/48)

## 现象

其他 App（Safari、VS Code 等）处于全屏 Space 时，点击状态栏图标不出现状态面板；
切回普通桌面 Space 后，面板其实已经在那里打开了。参照物是 CC Switch 之类的 App，
它们在全屏下可以正常弹出。

## 根因

`NSPopover.show(relativeTo:of:preferredEdge:)` 创建的背后窗口
（`_NSPopoverWindow`）**默认不带任何 Space 行为**。本 App 是 `.accessory`
（`LSUIElement`），状态栏窗口存在于当前 Space，全屏时就是那个全屏 Space；而 popover
的背后窗口因为没有 `NSWindowCollectionBehavior` 归属信息，被放到了这台 accessory
进程原本所在的桌面 Space。于是面板确实「打开了」，只是开在了全屏 App 后面。

公开 API 里没有让 `NSPopover` 直接指定 Space 行为的入口，但背后的 `NSWindow` 在首次
`show` 之后就可以拿到：`popover.contentViewController?.view.window`。给它补上

- `.canJoinAllSpaces`：覆盖普通 Space；
- `.fullScreenAuxiliary`：**其它 App** 的全屏 Space 只接受带这个标志的窗口。

两者缺一不可。

## 决定性证据：`.moveToActiveSpace` 与 `.canJoinAllSpaces` 互斥

不能直接 `insert`，否则可能**直接终止进程**。本机探针（macOS 27.0 / Swift 6.4）实测：

```bash
# 取一个窗口，先置 .moveToActiveSpace，再插入 .canJoinAllSpaces
window.collectionBehavior = [.moveToActiveSpace]
window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
```

```
after setting moveToActiveSpace: raw=2 canJoinAllSpaces=false moveToActiveSpace=true
about to insert canJoinAllSpaces + fullScreenAuxiliary
*** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
reason: 'window behavior cannot be both NSWindowCollectionBehaviorCanJoinAllSpaces
and NSWindowCollectionBehaviorMoveToActiveSpace'
[exit 134]
```

同一实验里先 `remove(.moveToActiveSpace)` 再插入，则得到
`raw=257`（`canJoinAllSpaces | fullScreenAuxiliary`），无异常。因此顺序是硬性要求，
而不只是风格问题。

```swift
collectionBehavior.remove(.moveToActiveSpace)
collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
```

## 修复

- 新增 `Sources/StatusTrioCore/UI/PopoverWindowPlacement.swift`：
  `NSWindow.enableDisplayOnFullScreenSpaces()`，按上面的顺序补 Space 行为，Space 之外的
  其它 `collectionBehavior` 位保持不变。
- `Sources/StatusTrioCore/UI/StatusBarController.swift` 的 `presentPopover`：在 `show(...)`
  之后、`makeKey()` 之前调用它。状态栏与 Dock 图标两条入口共用 `presentPopover`，因此
  两条路径行为一致（符合 AGENTS.md 的菜单栏 / Dock 一致性要求）。

必须放在 `show` 之后：`NSPopover` 在首次显示之前没有背后窗口。

## 验证

| 项目 | 结果 |
|---|---|
| `swift test --filter PopoverWindowPlacementTests` | 3 个测试通过（含异常守卫用例） |
| `swift test`（全量） | 无新增失败；见下方「已知环境性失败」 |
| `swift build -c release` | 通过 |
| `bash scripts/build-app.sh release no-open` | 产出 `dist/StatusTrio.app`，ad-hoc 签名通过 |
| 真机全屏弹出 | **通过**：维护者在 macOS 27 上确认，全屏 App 下点击状态栏图标可正常弹出 |

### 已知环境性失败（与本次改动无关）

在受限沙箱中运行测试时，以下两个用例在 **`origin/main` 干净基线**上同样失败，原因是
测试需要访问工作区之外的资源：

- `WirelessListModelsTests.testKeychainPasswordStoreAddsReadsUpdatesAndCleansItsOwnItem`
  —— 写入登录钥匙串被拒绝，`save` 返回 false、解析得 `.noCredential`。
- `TestUserDefaultsTests.removingATestSuiteDeletesItsPreferenceFile`
  —— 需要删除 `~/Library/Preferences/…plist`，被文件沙箱拒绝。

## 复现与探针

无沙箱限制的环境下可以直接跑一个最小探针，观察 popover 背后窗口的默认 Space 行为：

```swift
popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
print(popover.contentViewController?.view.window?.collectionBehavior.rawValue as Any)
```

注意两点：探针必须是**真正的 app bundle**（`LSUIElement` + 正常 app 生命周期），
非 bundle 的进程里状态项不会真正挂到菜单栏、`popover.show` 也不会成功；
`.transient` 的 popover 在 App 未激活时不会显示，所以探针要先
`NSApp.activate(ignoringOtherApps: true)`。

## 排查过但未改动的相邻风险

全屏场景下还考虑过两个可能同时存在的问题。真机确认后它们都**不需要改动**，记录在此以便
日后出现类似症状时优先排查，不必重新推演：

1. **激活策略**：`presentPopover` 用 `NSApp.activate(ignoringOtherApps: true)` 抢先激活，
   这是 14+ 上被协作式激活限制的旧 API。若日后出现「全屏下偶发不弹出」，下一步查这里
   （`.transient` 的 popover 在 App 未激活时会被立即关闭）。
2. **外部点击关闭监视**：`installPopoverDismissMonitor` 用全局 mouseDown 关闭面板。
   实测全屏 Space 下的事件序列没有产生「开了又被立刻关掉」。
