# Swift 工具链 CI 兼容性与失败记录

本文记录 Status Trio 在 GitHub Actions 上发布时遇到的工具链兼容问题，以及后续开发和发布必须遵守的规则。

## 结论

本机是 Xcode 27 / Swift 6.4，CI（`macos-26`）是 Xcode 26.6 / Swift 6.3.3，两者的语法支持、诊断和代码生成行为仍可能不同，不能只用本机 `swift test` 证明代码可以发布。CI 工具链必须作为最低兼容标准。

下表中 2026-09-19 之前的记录都发生在旧 CI 工具链（`macos-15` / Xcode 16.4 / Swift 6.1.2）上：`isolated deinit`、`weak let`、`Bundle.module` 资源布局、IRGen 崩溃这些具体症状属于那个编译器，而由它们归纳出的规则至今有效。

## 失败记录

| Run | 失败阶段 | 根因 | 修复方式 |
| --- | --- | --- | --- |
| `34753548674` | `Run tests` | `isolated deinit` 在 Swift 6.1.2 需要实验开关，默认不可用 | 移除 `isolated deinit`，改为普通 `deinit` 和显式清理 |
| `34753630833` | `Run tests` | 尝试启用 `IsolatedDeinit`，生产编译器不允许 | 不依赖该实验特性，直接改写生命周期清理 |
| `34753843803` | `Run tests` | 测试中的 `weak let` 在 Swift 6.1.2 非法 | 改为 `weak var` |
| `34753912541`、`34754021368`、`34754087160` | `Run tests` | `Bundle.module` 在 CI 中的 `lproj` 资源布局/大小写与本地不同 | 使用路径查找并同时尝试标准名和小写名 |
| `34758026894` | `Run tests` | Swift 6.1.2 IRGen 在处理 `Binding.set: localization.setPreference` 方法引用时崩溃 | 改写为显式闭包，避免触发 thunk 代码生成 |
| `34758129632` | 全部通过 | 1.0.1 / build 2 发布成功 | 保留上述兼容性修复 |
| `35293247382` | `Run tests` | 测试用 `drainMainActorTasks()` 假定 `AsyncStream` 消费任务一定已完成；CI 调度较慢时仍读到更新前的 `currentDevice` | 测试改为有超时上限地等待目标状态，不再依赖单次主线程排空；后续预检 `35293533279` 全部通过 |
| `35307956823` | `Upload release artifacts` | runner 向 GitHub artifact 服务建 artifact 的请求超时（`Failed to CreateArtifact: Unable to make request: ETIMEDOUT`），发生在编译、测试、打包全部成功之后 | 与代码和工具链无关，无代码改动；重跑同一 run 的失败 job 后全部阶段通过 |
| `35316867111` | `Run tests` | 新增的图标合并重绘测试在断言前固定 `Task.sleep(200ms)`；Swift Testing 会同时启动整轮测试，CI 上主 actor 被排满的时间超过该固定等待，coalescer 的尾部重绘还没执行 | 测试改为轮询目标状态（5 秒上限，命中即返回），不再依赖固定睡眠；后续预检 `35317347672` 全部通过 |
| `35375443023`（fork 非发布预检） | `Build, sign, notarize, and publish` | 使用 `version=1.2.1`，但仓库没有 `release-notes/1.2.1`；前置校验允许非发布时跳过，`scripts/release.sh` 仍要求该目录存在。Swift 6.1.2 测试已通过，尚未进入 release 构建 | 保持音频代码提交 `55983e2` 不变，改用已有说明的 `version=1.2.0`、递增的 `build=10`、`publish=false`；后续预检 `35375769964` 的测试、通用 release 构建、DMG 打包和 artifact 上传全部通过 |
| `35447073294` | `Run tests` | `SettingsRowHitAreaTests.testPreferenceCheckboxRowUsesFullRowHitArea` 失败（`got [14.0]`）。该测试把 `NSHostingView.subviews` 当作命中区代理；macOS 26 SDK 把 `.checkbox` 样式的 `Toggle` 画成 14×14 的 AppKit `Checkbox` 加一个 SwiftUI 标签，脱离窗口时不存在任何全宽子视图。旧工具链（Xcode 16.4）与本机 macOS 27 都会生成全宽 `_FocusRingView`，所以失效的是探针的假设，不是产品行为 | `interactiveSubViewSizes` 改为先把行放进已 `makeKeyAndOrderFront` 的 `NSWindow` 再测量：窗口的 key-view proxy 在 macOS 26 上正好是 300 pt 宽；后续预检 `35448004467` 通过 |
| `35447273818` | `Run tests` | 同一根因的诊断复现（临时 dump 视图树以取得 macOS 26 上的实测尺寸与类名） | 同上 |
| `35447521372` | `Run tests` | `AppIconControllerTests.visibleDockRendersStatusChanges`（Swift Testing）偶发失败：`renderCount → 0`，期望 `1`。上一版修复在探针里调用了进程级的 `NSApplication.shared.setActivationPolicy(.accessory)`，改变了其他测试判断 Dock 是否可见的前提 | 从 `interactiveSubViewSizes` 移除该调用，只保留窗口，并在 `defer` 里 `orderOut` 加清空 `contentView`；后续预检 `35448004467` 通过 |
| （本轮，非失败记录） | `swift build --build-tests` | 本机 Xcode 27 / Swift 6.4 对四处测试里的 `weak var weakMonitor` 报 `weak variable ... was never mutated; consider changing to 'let' constant`。编译器的建议是 `weak let`，但 `AGENTS.md` 明令禁止该写法，且没有证据表明 CI 的 Swift 6.3.3 接受它 | 不采用 `weak let`。把这四处改成 `Tests/StatusTrioCoreTests/DeinitProbe.swift` 里的 `DeinitProbe.track(_:)`，弱引用以 `weak var` 存储属性保存（写法仍满足规则），断言内容与顺序不变 |
| `35614298374` | `Run tests` | 新增的 `BluetoothSummaryTests.testDevicesWithoutALevelKeepTheirNameOnly` 断言了 `机灵的耳机` 与 `MX Keys` 拼接后的先后。摘要行按系统 collation 排序，而 ICU collation 与语言有关：CI runner（英文）把 `MX Keys` 排在前，开发机（中文）把中文名排在前。本地 `swift test` 与 `swift build -c release` 全绿，所以失效的是断言（对混合脚本排序的假设），不是产品缺陷 | 把排序规则改成「AirPods 无条件最前、其余按名称」（`BluetoothDevicePresentation.grouped`），断言不再依赖 collation；后续预检 `35615262052`（`build=24`）全绿 |
| `35718713396`（1.3.0 正式发布，`build=13`） | `Build, sign, notarize, and publish` 末尾的 appcast 发布回读（`scripts/release.sh`） | 测试、构建、签名、DMG、Release 上传、appcast 提交（`8519984`）全部成功后，PUT 完成仅 2 秒即用 Contents API 回读 `appcast.xml?ref=main`，撞上 GitHub Contents API 的最终一致性窗口，读到旧 blob 而误报 `published appcast does not contain build 13`。与工具链、代码、说明文件无关 | 回读改为带退避的重试（最多 6 次、间隔 5 秒），重试全部用尽才失败；已手动回读远端 appcast 确认 build 13 条目完整（12 titles + 12 descriptions、en 首位、edSignature 与 DMG 长度 4244534 一致），1.3.0 发布四项核验通过；重试逻辑经桩测（stale→stale→fresh 通过、恒 stale 失败并退出 1）验证，详见文末专节 |
| （本地，非失败记录） | 本机 `swift test` | 新加的 `VolumeFeedbackTests.preferenceTreatsAMissingKeyAsEnabled` 想用 suites 断言「键不存在时按开启处理」，而 `UserDefaults(suiteName:)` 的搜索链在 suite 域之后仍会落到 `NSGlobalDomain`：全新 suite 读到的是本机 `com.apple.sound.beep.feedback`。开发机把这个开关关成 `0`（0 = 关）之后该测试即失败，CI runner 上（该键缺失）却一直是绿的——失效的是测试对「suite 隔离」的假设，不是产品行为 | 把判断拆成纯函数 `SystemVolumeFeedbackPreference.isEnabled(storedValue:)`，「缺失按开启」由它覆盖，suite 只留给显式写值的用例；顺带给两个未注入 feedback 播放器的既有 store 测试补上假播放器，免得在开关打开的机器上跑测试时真的出声。后续预检 `35851597428` 全绿 |

> **本轮结束时构建不是零警告：** 上面的修复只清掉了 `weak var` 那 4 条 `WeakMutability` 和 Task 1 的 1 条 `String(cString:)`，共 5 条；剩下 **2 条**警告是 `WiFiPasswordStore.swift` 的 `kSecUseAuthenticationUIFail` / `kSecUseAuthenticationUIAllow` 弃用，属于 R-12（Keychain 加固）计划，class B，尚未开始。不要把本轮记录读成「构建已经干净」。

## 35375443023：非发布预检缺少下一版本说明

上述音频预检在 `hhh2210/status-trio` fork 执行，使用与上游相同的
macOS 15 / Xcode 16.4 / Swift 6.1.2 workflow：
[失败记录](https://github.com/hhh2210/status-trio/actions/runs/35375443023)、
[同一代码提交的通过记录](https://github.com/hhh2210/status-trio/actions/runs/35375769964)。
两次均未发布 Release 或更新 appcast。

合并前又在上游仓库以同一 workflow 复跑了一次非发布预检
[`35418503401`](https://github.com/lingyired/status-trio/actions/runs/35418503401)
（`version=1.2.0`、递增的 `build=10`、`publish=false`）：574 个 XCTest（3 跳过）、
146 个 Swift Testing 全部通过，通用 release 构建、`StatusTrio-1.2.0.dmg` 打包和
artifact 上传成功，未发布 Release 或更新 appcast。该次预检验证的是 Swift 代码提交
`e22cd13`；其后只有记录 CI 历史的 Markdown 提交。

同一个门槛在 2026-09-23 又踩了一次，这次是触发后才发现的：预检
[`35837434234`](https://github.com/lingyired/status-trio/actions/runs/35837434234)
用 `version=1.3.2` 派发，而仓库当时还没有 `release-notes/1.3.2/`。前置的
`Validate appcast notes` 会打印「目录不存在，跳过校验」并成功，真正拦人的是稍后的
`scripts/release.sh`——它检查 `release-notes/$VERSION` 目录的那段在 `PUBLISH` 判断之外，
所以非发布预检照样要过这一关。该 run 在测试跑完前取消，取消不产生 Release、tag 或
appcast 改动。

现在的做法：预检一个还没发布过的版本时，先把 `release-notes/<version>/` 的 `en.md` 与
`zh-Hans.md` 一起提交上（`publish=false` 只警告缺少其余 10 种语言，`publish=true` 才要求齐全）。
补上文案后复跑 [`35837523924`](https://github.com/lingyired/status-trio/actions/runs/35837523924)
（`version=1.3.2`、`build=15`、`publish=false`）：760 个 XCTest（6 跳过）、
247 个 Swift Testing 全部通过，通用 release 构建、`StatusTrio-1.3.2.dmg` 打包和 artifact
上传成功，appcast 校验通过（2 titles and 2 descriptions, en first），未发布 Release 或
更新 appcast。该次预检验证的是 Swift 代码提交 `23a3d9f`。

1.3.3 的非发布预检 [`35851597428`](https://github.com/lingyired/status-trio/actions/runs/35851597428)
（`version=1.3.3`、`build=16`、`publish=false`）在推送 `feat/volume-feedback-sound`
分支后派发，一次通过：762 个 XCTest（6 跳过）、255 个 Swift Testing（36 个 suite）
全部通过，通用 release 构建、`StatusTrio-1.3.3.dmg` 打包和 artifact 上传成功。
该次预检验证的是 Swift 代码提交 `734fc3a`（音量反馈音的实现、测试清理和 1.3.3 文案），
未发布 Release、未创建 tag、appcast 未更新。派发前先在本地跑通了 `swift test` 与
`swift build -c release`，并把 `release-notes/1.3.3/` 的 `en.md` 与 `zh-Hans.md`
随分支一起提交，所以这次没有再撞上上一节那个 notes 目录门槛。

## 失败记录规则

每次 GitHub Actions 失败都必须追加到上表，至少包含：

- workflow run ID
- 失败阶段或 job
- 可复现的直接根因
- 修复方式
- 后续 CI 预检验证结果

不能只记录“重跑后通过”。如果不能确认根因，先记录已知证据和下一步排查方向，确认后再补充。

## 35293247382：测试同步竞态

这次非发布预检在 `SystemStatusStoreTests` 失败：

- `testSetVolumePreservesCurrentOutputDevice` 在 CI 中读到 `currentDevice == nil`
- 同一测试在本机和后续定向运行中通过
- 失败测试使用 `await drainMainActorTasks()` 推进主线程，但该方法只排空一次
  MainActor，不能保证 `AsyncStream` 的消费任务已经执行

修复方式是等待明确的业务状态，而不是等待调度时序：

```swift
await waitUntil { store.liveVolume.currentDevice == currentDevice }
```

`waitUntil` 使用 1 秒上限并在超时后让测试失败。`testSetVolumeUpdatesVisibleVolumeImmediately`
也使用同样方式等待初始音量，避免同类竞态。

修复后的非发布预检 `35293533279` 已完整通过，包括 `Run tests`、release 构建、
签名、产出上传和 workflow 收尾阶段。

## 当前这次是否和编码有关

有关系，但不是业务逻辑错误。

`set: localization.setPreference` 在 Swift 6.4 中合法，在语义上也没有问题；问题出在 Swift 6.1.2 的 IRGen 对“带 actor isolation 的方法引用转换为函数值”的代码生成存在编译器缺陷。显式闭包没有改变行为，只是避免了触发该编译路径：

```swift
// 不要这样写：会在 Swift 6.1.2 触发 IRGen 崩溃
set: localization.setPreference

// 这样写：行为相同，但不生成触发 crash 的转换
set: { newPreference in
    localization.setPreference(newPreference)
}
```

所以结论是：**代码写法是当前崩溃的触发条件，但根因是 CI 与本地 Swift 工具链不一致。** 后续开发需要同时处理这两件事。

## 35307956823：artifact 上传超时

这次非发布预检（`version=1.1.1`、`build=9`、`publish=false`，分支 `fix/dock-icon-after-update-check`）在最后一步失败：

- `Run tests`、`Build, sign, notarize, and publish` 均通过，说明 Xcode 16.4 / Swift 6.1.2 下编译、测试、打包都正常
- 只有 `Upload release artifacts` 失败，报错是 `Failed to CreateArtifact: Unable to make request: ETIMEDOUT`
- 该步骤带 `if: always()`，失败原因是 runner 与 GitHub artifact 服务之间的请求超时，属于基础设施抖动

因为失败点在所有编译与测试阶段之后，且报错不包含任何编译或测试诊断，这次失败与代码无关，没有对应的代码修复。处理方式是重跑失败 job，重跑后 `Set up job` 到 `Complete job` 全部通过（包括 artifact 上传）。

判断同类失败的标准：失败的必须是最后一个上传/清理步骤，并且日志里没有任何 Swift 编译、链接或测试输出。如果失败出现在 `Run tests` 或 `Build, sign, notarize, and publish`，必须按上面的规则排查代码。

## 35331580264：蓝牙电量读取的所有权竞态

这次非发布预检在 `BluetoothBatteryLevelHandoffTests` 失败：

- `testDetailPageKeepsReadingLevelsAfterLeavingTheSummary` 在最后一行
  `XCTAssertFalse` 失败，即从详情页返回摘要后电量读取没有被重新打开
- 同一测试在本机通过，因此不能按抖动处理

直接根因不是工具链问题，而是一个真实的顺序竞态：摘要行和详情页**共用一个布尔
标记**来决定是否读取电量。SwiftUI 在切换子树时，离开方与进入方的生命周期回调
顺序并不固定，实测两种情况都会出现：

```
去详情页：summary.task → detail.appear → summary.disappear
返回摘要：detail.disappear → summary.task → summary.appear
```

于是“最后写入者获胜”：离开摘要时会把详情页刚申请的电量读取关掉，详情页每个
设备都显示“不可用”；返回摘要时又会因为标记被关掉而不再重开。

修复方式是让结果与顺序无关，而不是再去猜顺序：控制器改为按 token 记录**申领
计数**，只要还有任一界面持有申领就继续读取，最后一个释放时停止。

```swift
func requestBatteryLevels(_ token: String)
func releaseBatteryLevels(_ token: String)
```

摘要在“开关打开且连了 AirPods”时申领，详情页仅按开关申领，关闭 popover 时清空
全部申领。新增控制器级测试直接覆盖两种顺序、重复申领和关闭场景，不再依赖
SwiftUI 的时序。

修复后的非发布预检 `35332232060` 的 `Run tests`、release 构建、签名和产出上传
全部通过。

## 强制开发规则

### 1. 以 CI 工具链为准

发布环境的基准是：

- `macos-26`
- Xcode `26.6`
- Swift `6.3.3`

本机 Xcode 27 / Swift 6.4 的通过结果只能作为辅助验证，不能替代 CI。

### 2. 修改 Swift 代码后的最低验证

```bash
swift test
swift build -c release
```

涉及以下内容时，必须额外触发一次 `publish=false` 的发布预检：

- actor isolation、`@MainActor`、`Sendable`
- `deinit` 和生命周期清理
- SwiftUI `Binding`、方法引用和闭包
- 泛型、可选值和复杂类型转换
- `Bundle.module`、本地化资源或 SwiftPM 资源布局

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref <branch> \
  -f version=<next-version> \
  -f build=<next-build> \
  -f publish=false
```

等待并确认该 run 成功后再合并或发布。

### 3. 禁止使用仅在新工具链可用的写法

- 不使用 `isolated deinit`
- 不启用 `IsolatedDeinit` 或其他实验性编译器特性来绕过发布问题
- 不把 actor-isolated 方法直接当作闭包/函数值传递
- 不使用 `weak let`，weak 绑定必须是 `var`
  - 如果编译器因此报 `weak variable ... was never mutated`，不要照它的建议改成 `weak let`。用测试目标里的 `DeinitProbe.track(_:)`，把弱引用放进 `weak var` 存储属性。
  - 要推翻这条规则，必须同时提供 CI 工具链（`macos-26` / Xcode 26.6 / Swift 6.3.3）接受 `weak let` 的运行记录，然后才改 `AGENTS.md`。
- 不假设本地和 CI 的 `Bundle.module` 资源目录大小写或布局一致

### 4. 遇到编译器崩溃时的处理方式

以下症状表示应该缩小或改写触发表达式，而不是重试或改变发布参数：

- `error: compile command failed due to signal 6`
- `IRGenRequest`
- `SmallVector unable to grow`
- `fatal error encountered during compilation`

处理顺序：

1. 从堆栈中的 `While evaluating request IRGenRequest` 找到源文件。
2. 检查该文件最近新增的方法引用、闭包转换、actor isolation 和复杂泛型表达式。
3. 用显式闭包或拆分局部变量改写最小表达式。
4. 重新运行本地测试和 CI 预检。
5. 只有 CI 预检成功后，才允许触发 `publish=true`。

## 发布检查清单

- [ ] 版本号已明确，构建号大于线上 appcast 的最大构建号。
- [ ] `swift test` 通过。
- [ ] `swift build -c release` 通过。
- [ ] 涉及兼容性敏感代码时，`publish=false` 的 GitHub Actions 预检通过。
- [ ] `publish=true` 的发布 workflow 成功。
- [ ] GitHub Release 有 DMG 和 `.sha256` 文件。
- [ ] 线上 `appcast.xml` 的版本、构建号、长度和 EdDSA 签名已更新。
- [ ] 未配置 Developer ID / notarization 时，明确说明 Ad-hoc 签名和首次安装限制。

## 工具链迁移记录

日期：2026-09-19。

issue [#40](https://github.com/lingyired/status-trio/issues/40) 的根因不是缺代码，而是**构建 SDK 太旧**。
`scripts/build-app.sh` 从 `b728e6c`（2026-09-13）起就带有用 `vtool` 改写 `LC_BUILD_VERSION.sdk`
的修补，但 CI 一直是 `macos-15` + Xcode 16.4（SDK 15.5），`if SDK >= 26` 从未成立，
这段修补在任何一次发布里都**没有生效过**——线上 app 的 `sdk 15.5` 就是证据。macOS 依据
`sdk` 字段判断 app 是否采纳当前设计语言，所以菜单栏面板一直停在 Tahoe 之前的磨砂观感。

迁移把 CI 换成 `macos-26` + Xcode 26.6（Swift 6.3.3）来激活它，并补上三道护栏：

- `scripts/build-app.sh` 在 **`swift build` 之前**就以退出码 2 失败（SDK < 26），不再静默跳过。
  放在编译前是有意的：放在后面会先花掉一次完整编译，并留下一个能运行、观感却是旧的 bundle，
  正是这次要消灭的那种「构建成功、观感悄悄回退」。
- `minos` 从产物读回后原样写回，不再硬编码 `15.0`；**并且**与 `Support/Info.plist` 的
  `LSMinimumSystemVersion` 交叉比对，不一致就失败。只把产物里的值读回来再写回去是不够的——
  那样断言只是自我比较，`Package.swift` 抬高 `platforms` 时仍会静默产出 macOS 15 用户
  无法启动的包。
- `scripts/verify-platform-version.sh` 逐架构断言 `minos` 与 `sdk`，期望值取
  `LSMinimumSystemVersion`（一份独立声明，而不是产物自身的值），由构建脚本自动调用，
  本地构建与 CI 预检都会执行。

非发布预检 [`35452394846`](https://github.com/lingyired/status-trio/actions/runs/35452394846)
（`version=1.3.0`、`build=11`、`publish=false`）通过：608 个 XCTest（3 跳过）与 146 个
Swift Testing 全绿；通用 release 构建的两个切片都是 `minos 15.0 / sdk 26.0`，
`LC_BUILD_VERSION check passed`；DMG 打包与 artifact 上传成功，未发布 Release 或更新 appcast。
这次预检跑的是加了下面那几道护栏、并且页脚显示运行版本的代码，也就是说 `minos` 与
`LSMinimumSystemVersion` 的交叉比对在 CI 上确实执行并通过了。

同一条分支上更早两次通过的预检是 `35449290621`（`build=10`，护栏加强后的代码）与
`35448004467`（`build=10`，护栏加强之前）。

本次迁移过程中修掉的三个失败 run 见上面的失败记录表：`35447073294`、`35447273818`、`35447521372`。

### 复审后追加的护栏（2026-09-19）

整条分支复审时发现上面第二道护栏原本不成立：`build-app.sh` 把产物里的 `minos` 原样回传给
断言脚本，断言等于拿产物的值和它自己比，`Package.swift` 抬高 `platforms` 时必然通过。
现在是产物值 vs `LSMinimumSystemVersion` 的交叉比对，任一侧改动而另一侧没跟上都会失败。

同一次复审还改了两处：

- `SettingsRowHitAreaTests` 的探针原本固定等 50 ms；这个仓库已经因为固定睡眠吃过两次
  CI 失败（见上表 `35293247382`、`35316867111`），现在改为 2 秒上限的轮询。
- `release-notes/1.3.0/` 的 12 个文件原本写「macOS 15 及以上不受影响」，与同一条目的标题
  「macOS 26 及以上的原生 Liquid Glass」自相矛盾——受影响的正包括 macOS 26+。现改为
  「macOS 15–25 的观感保持不变」。`README.md` / `README.zh-CN.md` 的系统要求也补上了
  「构建需要 macOS 26 SDK」。

### 之后的跟进改动（2026-09-19）

- `Support/Info.plist` 的构建号由 10 提到 **11**。原因：开发机本地可能装着比线上 appcast 更超前的
  构建（例如 1.2.1/10），而 Sparkle 比较的是**已安装 app** 的 `CFBundleVersion`，`1.3.0 (10)`
  不会推送到这类机器。构建号的最终取值仍在发布时决定，判断基准是**已发布的 appcast**（当时为 9），
  不是本地已安装的版本。
- 弹窗页脚在「设置」按钮右侧、⋯ 菜单左侧显示运行版本（如 `1.3.0 (11)`）；开发构建仍在按钮文字里
  保留「开发版 · <代号>」。对比不同构建或排障时不必再打开「设置 → 关于」。

### issue #48 的预检（2026-09-20）

菜单栏面板在全屏 Space 下不弹出（[#48](https://github.com/lingyired/status-trio/issues/48)）的修复
新增了 `NSWindow` 扩展，属于 §2 的 `@MainActor` 范围，因此在分支
`fix/issue-48-fullscreen-popover` 上跑了一次非发布预检
[`35456441704`](https://github.com/lingyired/status-trio/actions/runs/35456441704)
（`version=1.3.0`、**`build=12`**、`publish=false`）：608 个 XCTest（3 跳过）与 149 个
Swift Testing 全绿，两个切片均为 `minos 15.0 / sdk 26.0`，DMG 与 artifact 上传成功，未发布。
`build=12` 大于线上 appcast 的最大构建号 9，也大于 `Support/Info.plist` 当前记录的 11。
根因与工程细节见 [fullscreen-popover-investigation.md](fullscreen-popover-investigation.md)。

### 方法引用改写的预检（2026-09-20）

`StatusBarController` 的 8 个弹窗回调、`SettingsDisclosureRow` 的 `toggle`、以及
`WiFiNetworkListView` 的两处 `dismiss.callAsFunction` 原本以方法引用（而非显式闭包）的形式
作为函数值传递，这正是 §2 的 `@MainActor` 范围，也是 `34758026894` 崩溃的同一类代码形状。
本次在分支 `fix/class-a-hardening`（计划 `docs/superpowers/plans/2026-09-20-toolchain-method-reference-compliance.md`）
上跑了一次非发布预检
[`35495412938`](https://github.com/lingyired/status-trio/actions/runs/35495412938)
（`version=1.3.0`、**`build=13`**、`publish=false`）：

- `Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、
  `Upload release artifacts` 全部成功；`Validate Sparkle signing secret` 与 `Prepare release notes`
  按 `publish=false` 跳过——即未发布 Release、未改动 appcast。
- `Run tests`：**624 个 XCTest（6 跳过，0 失败）** 与 **163 个 Swift Testing / 27 个 suite** 全绿。
- 两个切片均为 `minos 15.0 / sdk 26.0`，即 macOS 26 SDK 断言成立。
- `build=13` 大于线上 appcast 的最大构建号 9，也大于 `Support/Info.plist` 当前记录的 11。

这次预检同时验证了新增的强制门禁：`Tests/StatusTrioCoreTests/ForbiddenPatternGuardTests.swift`
在 `swift test` 内运行 `scripts/check-forbidden-patterns.sh` 及其 `--self-test`，因此**在守卫的覆盖范围内**
重新出现的方法引用会让 `Run tests` 失败，无需改动任何 workflow 文件。守卫当前的覆盖范围与非目标
（脚本头部列有同一份清单）是：

- 会扫描的函数值位置：参数标签 `action:`/`get:`/`set:`/`using:`/`block:`/`perform:`、
  `request*:` 与 `open*:` 两个回调族、`on[A-Z]…:` 回调族（锚定在词边界上，因此
  `connectionOptions:`、`iconSize:` 不会误判成 `on…:`），以及
  `.map`/`.compactMap`/`.filter`/`.forEach`/`.sink`/`.assign` 与 `.callAsFunction`。
- 判定规则：带接收者的**点号成员引用**（`receiver.method`）只要 `Sources/` 下存在同名 `func`
  声明，不论参数个数都算违规——这正是 `34758026894` 的崩溃形状
  `Binding(get: { 0 }, set: loc.setPreference)`；**裸标识符**仍要求 `Sources/` 下存在零参数
  `func <name>()`，唯一的例外是 `on[A-Z]…:` 回调族（该族期望的闭包本身带参数，例如
  `Slider(onEditingChanged: (Bool) -> Void)`，所以 `onEditingChanged: handleVolumeEditing`
  算违规）。其余非目标见脚本头部。
- **不覆盖**：`Tests/` 下的任何代码。扫描只遍历 `$ROOT/Sources`，所以守卫通过并不代表测试目标里
  没有方法引用；编译层面的最终判据仍然是本预检
  （`swift test` + `swift build -c release` + 非发布 release workflow）。

#### 加宽后的复核（`build=14`）

终审发现守卫的覆盖范围小于分支的声明：`StatusPopoverView` 的三个 `store.*` 回调
（`onVolumeChange`/`onToggleMute`/`onSelectOutputDevice`）、`VolumeControlsView` 的
`onEditingChanged` 与 `perform: synchronizeVolume`、`IconGuideView` 的 `perform: restartPulse`
共六处仍是方法引用，而 `34758026894` 的原始崩溃形状（`Binding.set: … setPreference`，**带一个
参数**）当时被判为 `external` 而漏检。这六处已改为显式闭包，并按上一节所述的规则加宽守卫
（点号成员引用不再受零参数规则限制，新增 `perform:` 与 `on[A-Z]…:`），`--self-test` 由
6/6 + 7/7 变为 **10/10 + 7/7**。

改完之后重跑非发布预检
[`35496776064`](https://github.com/lingyired/status-trio/actions/runs/35496776064)
（`version=1.3.0`、**`build=14`**、`publish=false`）：`Validate appcast notes`、`Run tests`、
`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，624 个 XCTest
（6 跳过，0 失败）与 163 个 Swift Testing / 27 个 suite 全绿，两个切片仍为
`minos 15.0 / sdk 26.0`，未发布 Release、未改动 appcast。
**两次预检对应加宽前后的两个 HEAD，合并时应以 `35496776064` 为准。**

守卫仍有两个已知的、当前不触发的假阳性路径，作为残留项记录而非继续扩大改动范围：一是点号分支
先于「转发闭包」豁免判断，因此 `Button(action: self.openSettings)` 这类**点号**转发闭包，在
`Sources/` 下恰好存在同名 `func openSettings()` 时会被误判为违规；二是转发的声明形状要求写成
`label name: … ->`，因此省略外部标签的闭包参数（`func f(read: (…) -> …)`）不再被豁免。两者在
当前代码树上都不产生任何输出（守卫退出 0），一旦出现按脚本头部的 `ALLOWED` 名单逐条标注即可。

### 状态轮询调度的预检（2026-09-20）

`SystemStatusStore` 的兜底轮询原本每 5 秒无条件唤醒一次，且 `Task.sleep` 没有
`tolerance`，无论 popover 是否打开、显示器是否睡眠都照跑。本次在分支
`fix/class-a-polling`（计划 `docs/superpowers/plans/2026-09-20-status-poll-scheduling.md`）
上做的改动是：给兜底 sleep 加 `interval / 5` 的 tolerance；把默认间隔由 5 秒提到 15 秒
（可调范围仍是 5...60 秒，用户选过的值仍然优先）；无可见界面时只刷新电池，Wi-Fi 与音量
改到每第 4 个 tick；显示器睡眠时整个 tick 跳过，任一唤醒通知都会清掉该标志并先
`recoverAll()` 再 `refreshAll()`；`applyVolume` 在值未变化时不再重复发布 `liveVolume`。

> **补齐（预检 `35513133152` 之后）：** 显示器睡眠的跳过当时没有上限，而「显示器单独睡眠」
> （屏保、显示器休眠定时器、系统不睡眠）只有 `screensDidWakeNotification` 一个清除入口。
> 该通知一旦丢失，`batteryMonitor.refresh()` 会在整场会话里停摆，画进菜单栏图标的电量
> 就此冻结。现补上 `maximumDisplayAsleepSkips`：连续跳过 20 个 tick（默认间隔 15 秒即
> 5 分钟）后强行刷新一次并清零计数，任一唤醒通知也会清零。因此丢一次通知最多只会让
> 每个上限损失一次刷新，而不是让轮询停摆整场会话。

这一步牵涉 `@MainActor` 状态与 `deinit`（新增两个 observer token，仅由 `deinit` 与 `stop()`
移除），因此按规则跑了非发布预检
[`35513133152`](https://github.com/lingyired/status-trio/actions/runs/35513133152)
（`version=1.3.0`、**`build=15`**、`publish=false`）：`Validate appcast notes`、
`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，
**636 个 XCTest（6 跳过，0 失败）** 与 **163 个 Swift Testing / 27 个 suite** 全绿，
两个切片均为 `minos 15.0 / sdk 26.0`，未发布 Release、未改动 appcast。

`build=15` 是因为 `12`（issue #48 全屏修复的预检，见上）、`13`、`14` 都已被更早的预检
占用；它仍大于线上 appcast 的最大构建号 9 与 `Support/Info.plist` 记录的 11。
本轮的用户可见影响是有界的：状态面板与设置窗口都关闭时，Wi-Fi 与音量的读数最多滞后
4 个 tick（默认间隔下 60 秒），这段滞后正常由推送通道覆盖；电池每个 tick 都刷新，
想恢复旧节奏的用户也可以在设置里选 5 秒。

> **⚠️ 构建身份不一致（必读）：** 现有的「改动前」基线取自**线上安装的 1.2.1 / build 10**，
> 不是本分支（工作树为 1.3.0）的构建。两者不是同构建对比，该数字只能作为背景参考，
> 不能当作本分支改动前后的对照。

功耗对比只记录了**改动前**的基线（线上安装的 1.2.1/10，空闲采样 20 次：平均 CPU 0.125 %、
RSS 25 MB、累计 idle wakeups 0；另一次在界面打开状态下的采样为平均 CPU 0.225 %、
RSS 134 MB、20 秒累计 240 次 idle wakeups——两次采样条件不同，不能互相比较）。

> **⏳ 改动后采样：发布 1.3.0 之前必须完成（当前仍未完成）。** 发布说明已经宣传了这项节省，
> 因此必须在发布前、在同一台机器上，用本分支自己的 dev bundle 采集，并把改动前后两个
> 数字一起记录到 PR。发布后再补测就没有意义了。命令如下（`scripts/build-worktree.sh`
> 会派生出独立的 dev bundle id，不覆盖已安装的正式版）：
>
> ```bash
> # 先退出已安装的正式版，保证只有一个 StatusTrio 进程（dev bundle 与正式版可同时运行，
> # 两个 PID 会让 top -pid 报 "invalid option or syntax"）
> osascript -e 'tell application id "com.lingsmbp.StatusTrio" to quit'
> bash scripts/build-worktree.sh release no-open
> open dist/StatusTrio.app
> top -l 20 -s 1 -pid "$(pgrep -x StatusTrio)" | tail -5
> ```
>
> 本次预检未执行采样，是为了不在维护者的机器上多出一个菜单栏实例并触发权限弹窗；
> 这个理由只解释了当时的推迟，不能替代发布前必须拿到的证据。

### 有界自愈的第三次预检（`build=16`）

终审指出上一版的「显示器睡眠」标志只由两个唤醒通知清除：显示器单独睡眠时若那一条
`screensDidWakeNotification` 丢失，电池刷新会在整个会话里停住，而电池百分比是画进菜单栏
图标的——正是本计划禁止的「轮询永久停止 / 已绘制值变陈旧」。修复方式是给跳过加一个上限：
连续跳过 20 个 tick（默认 15 秒下约 5 分钟）后就照常刷新并清零，任一唤醒通知或任何一次真正
执行的 tick 也会清零。这样丢失一条通知的代价是被上限约束的一次多余刷新，而不是整个会话停摆。

该修复触及 `@MainActor` 状态，因此再次跑了非发布预检
[`35514169366`](https://github.com/lingyired/status-trio/actions/runs/35514169366)
（`version=1.3.0`、**`build=16`**、`publish=false`）：`Validate appcast notes`、`Run tests`、
`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，
**637 个 XCTest（6 跳过，0 失败）** 与 **163 个 Swift Testing / 27 个 suite** 全绿，
未发布 Release、未改动 appcast。**本分支合并时应以 `35514169366` 为准**（`35513133152`
对应有界自愈修复之前的 HEAD）。

同一次修复还按终审意见收尾了文档：发布说明改为「默认每 15 秒一次」并去掉了「watchdog /
看门狗」这类开发者词汇、改用 `.lproj` 里的既有术语；`2026-09-12-status-trio-design.md`
标记为 v1 设计快照；`2026-09-14-performance-optimization-design.md` 的间隔描述改为
实际的 15 秒 / 5...60 / 步长 5。

> **⏳ 仍然未完成：改动后的功耗采样（见上一节）。** 它不影响合并，但**必须在发布 1.3.0
> 之前**补上。

### 蓝牙轮询改写的预检（2026-09-20）

`BluetoothDeviceController` 原本每 15 秒 spawn 两次 `/usr/sbin/system_profiler`，且在用户授权并打开过 popover 之后**永不停止**；`deinit` 也不会移除两个 `NotificationCenter` observer、不会停 IOBluetooth 事件监视器和 CoreBluetooth 状态监视器。本次在分支
`fix/class-a-bluetooth`（计划 `docs/superpowers/plans/2026-09-20-bluetooth-polling-and-lifetime.md`）上把蓝牙改成推送驱动：每个刷新周期共用一份 profiler 报告（2 → 1 次 spawn）；单次读锁 + 一次合并的后续刷新；可见性 claim 门控的 30 秒兜底轮询；IOBluetooth 连接/断开通知 + 750 毫秒防抖；完整的 `deinit` 拆卸；以及**读队列退役 + 读看门狗**（两者必须同时存在：只加看门狗时重试会排在挂住的块后面）。

这一步是 `deinit` + `nonisolated(unsafe)` + `@MainActor` hop 的形状，因此按规则跑了两次非发布预检：

- [`35520306448`](https://github.com/lingyired/status-trio/actions/runs/35520306448)（`build=17`）—— 终审修复 wave **之前**的 HEAD。
- [`35521490583`](https://github.com/lingyired/status-trio/actions/runs/35521490583)（**`build=18`**）—— 修复 wave 之后，**合并以这次为准**：`Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，**668 个 XCTest（6 跳过，0 失败）** 与 **168 个 Swift Testing / 27 个 suite** 全绿，两个切片均为 `minos 15.0 / sdk 26.0`，未发布 Release、未改动 appcast。

终审修复 wave 修掉的一个真实缺陷值得记在这里：设备断开时 `BluetoothConnectionEventMonitor` 直接丢弃 `IOBluetoothUserNotification` token 而**没有 `unregister()`**，而 SDK 明确说明 token 在注销前一直有效——于是每一次断开都会在存活的监视器上永久泄漏一个注册，并在下次断开时多触发一次回调（注释还写着相反的话）。现已改为先 `unregister()` 再丢弃（断线与重连两条路径都覆盖），并加了通过计数 token 注销次数、可对旧代码失败（RED `[0, 0, 1, 1]`）的测试。

> **⏳ 仍未完成：改动前后的 spawn 次数实测**（计划 Task 7 Step 1）。它不影响合并，但和 R-03 的功耗采样一样，**必须在发布 1.3.0 之前**由维护者用 dev bundle 采集（`pgrep -x system_profiler` 采样：面板关闭时应为 0 次，蓝牙界面可见时约每 30 秒一次），或在合并记录中明确豁免。计划里没有记录任何推断出来的数字。

### Wi-Fi 扫描节奏的预检（2026-09-20）

Wi-Fi 页面原本在打开期间**每约 5 秒**做一次全信道 `scanForNetworks` 并 spawn 一个 `networksetup`（30 秒的周期循环只是下限，状态 yield 才是真正的驱动），返回摘要页后循环仍在跑；没有 Wi-Fi 网卡的 Mac 还会每 30 秒重建整套 CoreWLAN 事件栈。本次在分支
`fix/class-a-wifi`（计划 `docs/superpowers/plans/2026-09-20-wifi-scan-cadence.md`）上：加入可注入的扫描 worker/时钟/`minimumScanInterval`（30 秒），把 `refresh`（自动、间隔内复用缓存）与 `refreshNow`（显式、总是扫描）分开；三个用户主动路径（刷新按钮、无线开关、连接完成）改走 `refreshNow`；新增 `closeWiFiDetails()` 并在返回时调用，同时修掉一个既有的「扫描中 deactivate 会让 `state` 永久停在 `.scanning`」冻结；把无网卡时的恢复限制为 3 次重建。

这一步触及 `@MainActor` 状态，因此按规则跑了两次非发布预检：

- [`35528142630`](https://github.com/lingyired/status-trio/actions/runs/35528142630)（`build=19`）—— 终审修复 wave **之前**的 HEAD。
- [`35528756095`](https://github.com/lingyired/status-trio/actions/runs/35528756095)（**`build=20`**）—— 修复 wave 之后，**合并以这次为准**：`Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，**683 个 XCTest（6 跳过，0 失败）** 与 **168 个 Swift Testing / 27 个 suite** 全绿，两个切片均为 `minos 15.0 / sdk 26.0`，未发布 Release、未改动 appcast。

终审修复 wave 修掉的缺陷值得记在这里：`recoverIfAllowed` 把 `interfaceAbsentStreak` 的**自增放在 staleness 门控之前**，于是被门控刻意抑制的读也在消耗恢复预算——注释、测试名与测试注释都写着"计数重建次数"，代码却在数读次数，两者只在测试刻意使用的 30.001 秒读间隔下重合。生产中间隔更密（R-03 的 15 秒兜底 tick 加链路质量事件），预算约 45 秒就耗尽，实际只换到 1–2 次重建，而不是文档承诺的 3 次。现已把自增移到门控之后，并新增一条 **5 秒读间隔**的测试独立钉住"计数的是重建"（对旧代码 RED：`streak 3 != 1`、`restartCount 1 != 3`）。

> **⏳ 仍未完成：改动前后的扫描次数实测**（计划 Task 5 Step 5）。与上面两项一样不影响合并，但**必须在发布 1.3.0 之前**由维护者用 dev bundle 采集（`pgrep -x networksetup` 采样：间隔内应为 0 次，页面打开时约每 30 秒一次，返回摘要后应为 0 次），或在合并记录中明确豁免。

> **记录在案的残留项（已裁定，不在本计划内修）**：无网卡恢复的 3 次上限**无法区分**"这台机器没有 Wi-Fi 硬件"与"有硬件但接口读卡在 nil"。后者在旧代码里会在 30–60 秒内自愈，现在 3 次重建后要等到睡眠/唤醒或连接失效才恢复，期间菜单栏与 Wi-Fi 页显示 `.unavailable`。计划有意收紧这项工作，发布说明也写明"尝试有限次数后等待唤醒或网络变化"；若要恢复慢速自愈，需要一个更慢的（例如每几分钟一次）上限后兜底，属后续改动的设计决定。

### 编译警告清理的预检（2026-09-21）

本计划清掉 7 处告警中的 5 处：把 `AudioOutputDeviceIcon.swift` 里废弃的 `String(cString:)` 换成 `String(decoding:as:)` 并把 `hw.model` 解析抽成纯函数以便测试；把三处测试文件里的 4 个 `weak variable … was never mutated` 改为通过新的 `Tests/StatusTrioCoreTests/DeinitProbe.swift` 以 `weak var` 存储属性观察释放——**没有**采用编译器建议的 `weak let`（`AGENTS.md` 禁止，且 CI run `34753843803` 记录旧工具链不接受该写法）。规则与决策已写入上表与 §3，并在 `AGENTS.md` 第 45 行加了指向 `DeinitProbe` 的括号说明（规则本身未放松）。

分支 `fix/class-a-icons`（计划 `docs/superpowers/plans/2026-09-20-compiler-warning-cleanup.md`）的非发布预检
[`35565582217`](https://github.com/lingyired/status-trio/actions/runs/35565582217)（`version=1.3.0`、**`build=21`**、`publish=false`）：
`Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，
**683 个 XCTest（6 跳过，0 失败）** 与 **170 个 Swift Testing / 27 个 suite** 全绿，未发布 Release、未改动 appcast。
终审修复 wave 之后只改了注释、测试名、一个泛型参数（`Unicode.ASCII` → `Unicode.UTF8`，用来恢复旧 `String(cString:)` 的解码契约）与计划文本，没有触及 actor isolation / `@MainActor` / `deinit` 形状，因此按既定规则**没有再跑一次预检**。

> **本计划结束时构建仍**有 2 处告警，都是 `WiFiPasswordStore.swift:108`、`:131` 的 `kSecUseAuthenticationUI*` 废弃提示，属于 **R-12（Keychain 加固，class B，尚未开始）**。上表已在"本轮，非失败记录"一行记录该决策与证据门槛：要推翻 `weak let` 规则，必须提供 CI 工具链（`macos-26` / Xcode 26.6 / Swift 6.3.3）接受该写法的运行记录。

> **终审发现的测试诚实性问题也已修正**：新增的"shrinking buffer"测试曾以系统调用重采样路径命名并声称其在缩容时返回 `""`，但它只调用纯解析函数，而实测缩容时得到的是缩短后的型号（`Mac15,9`）而非空串——即套件曾声称覆盖一个它并不覆盖的可见回退。现已改名为 `modelIdentifierParserHandlesEmptyAndUnterminatedBuffers`，删掉错误注释，并在计划的风险行里明确写出 **sysctl 失败路径未被测覆盖**。

## 35614298374：排序断言依赖了 locale（蓝牙电量默认开启，第 2 轮）

分支 `fix/bluetooth-battery-level-default`（设计 `docs/superpowers/specs/2026-09-20-bluetooth-battery-level-default-design.md`）的第二次非发布预检
[`35614298374`](https://github.com/lingyired/status-trio/actions/runs/35614298374)（`build=23`）在 `Run tests` 失败，唯一失败用例是新增的
`BluetoothSummaryTests.testDevicesWithoutALevelKeepTheirNameOnly`：

```
XCTAssertEqual failed: ("Optional("MX Keys、机灵的耳机 · L 93%")") is not equal to ("Optional("机灵的耳机 · L 93%、MX Keys")")
```

摘要行把已连接设备交给 `BluetoothDevicePresentation.grouped` 排序，那里用的是 `name.localizedCaseInsensitiveCompare`，即 ICU collation —— 与语言有关：CI runner（英文）把 `MX Keys` 排在 `机灵的耳机` 之前，开发机（中文）相反。本机 `swift test` 与 `swift build -c release` 都是绿的，因此这是**断言**的问题，不是产品缺陷；前面那次预检 `35610292554`（`build=22`）也不含这条用例。

不过它顺带暴露了一个真实取舍：AirPods 的多路电量是这一行的头条信息，不该因为名字的 collation 被挤到后面。修复把排序规则改成 **AirPods 无条件最前、其余按名称**（Connected / Not connected 两组内一致），`BluetoothDevice.isAirPods` 因此恢复，但用途只剩排序（产品 ID 命中或名字含 "airpods"；电量认领已不依赖它）。断言现在由规则决定顺序，`testAirPodsLeadTheRowRegardlessOfName` 用一个 collation 最靠后的名字钉住这条规则。

验证：[`35615262052`](https://github.com/lingyired/status-trio/actions/runs/35615262052)（`build=24`）`Validate appcast notes`、`Run tests`、`Build, sign, notarize, and publish`、`Upload release artifacts` 全部成功，**690 个 XCTest（6 跳过，0 失败）** 与 **180 个 Swift Testing / 28 个 suite** 全绿，未发布 Release、未改动 appcast。

## 35718713396：appcast 发布回读撞上 Contents API 最终一致性（1.3.0 正式发布）

1.3.0 正式发布 run [`35718713396`](https://github.com/lingyired/status-trio/actions/runs/35718713396)
（`version=1.3.0`、`build=13`、`publish=true`）在 `Build, sign, notarize, and publish`
的**最后一步**失败，错误来自 `scripts/release.sh` 的发布后回读校验：

```
Error: published appcast does not contain build 13.
```

时间线（取自该 step 日志）：

- 11:01:16 `Build complete!`，`LC_BUILD_VERSION` 检查通过（两架构 `minos 15.0, sdk 26.0`），
  `codesign` 校验通过；
- 11:01:43–47 `gh release create v1.3.0` 成功，DMG 与 sha256 随即上传为 Release 资产；
- 11:01:47 appcast 经 Contents API `PUT` 成功提交（main 上的 `8519984`）；
- 11:01:49 **仅 2 秒后**回读 `appcast.xml?ref=main` 做校验，读到旧内容，`exit 1`，整个 run 标红。

根因：GitHub Contents API 在写入成功后存在短暂的最终一致性窗口，紧接 `PUT` 的读取
可能拿到旧 blob。本次发布与 Swift 工具链、产品代码、说明文件均无关；除这条回读外，
发布的每一个环节都已实际完成。该路径只在 `publish=true` 时执行（`release.sh` 在
`PUBLISH=false` 时于第 238 行提前退出），且 `Release` 已存在时不允许复跑（第 243 行），
所以无法通过重跑同一发布来复现或验证。

修复：`scripts/release.sh` 的回读改为带退避的重试——最多 6 次、间隔 5 秒，期间读到
含目标 build 即视为成功，重试全部用尽才保留原错误信息并失败。错误文案未变，
`docs/superpowers/plans/2026-09-20-preflight-validator-and-appcast-sync.md` 中引用它的
测试断言不受影响。

验证：

- **发布四项核验（该 run 实际结果）**：`Run tests` 成功；DMG `StatusTrio-1.3.0.dmg`
  （4 244 534 字节）与 sha256 已在 Release 上；Release
  [v1.3.0](https://github.com/lingyired/status-trio/releases/tag/v1.3.0) 已发布，正文为规定的
  `# Version 1.3.0 （English + 中文， 中文在下方）` 双语格式并附首次安装命令；
  appcast 提交 `8519984` 已在 main，Sparkle 源已含 build 13。
- **远端 appcast 条目**：12 titles + 12 descriptions、`en` 首位、真实 `sparkle:edSignature`、
  `length=4244534` 与 Release 资产一致、无残留 `%VERSION%/%BUILD%` 占位符。
- **重试逻辑桩测**：用桩 `gh`（前 2 次返回旧内容、第 3 次返回含 build 13 的内容）执行
  release.sh 中的同一段回读代码，得到 `appcast_verified=true` 且仅调用 3 次；桩恒返回旧内容时，
  6 次用尽后打印原错误信息并以 1 退出。`bash -n scripts/release.sh` 语法检查通过。
- 本次改动只有 shell 与 Markdown，未触碰 Swift 代码，按规则无需新的工具链预检；
  下一次正式发布将真实行使这段重试。

## 35740301886：30 秒回读窗口仍不足，判据改到 git 层（1.3.1 正式发布）

1.3.1 正式发布 run [`35740301886`](https://github.com/lingyired/status-trio/actions/runs/35740301886)
（`version=1.3.1`、`build=14`、`publish=true`）在 `Build, sign, notarize, and publish`
的最后一步再次失败，用的正是上一条记录留下的重试窗口：

```
Published appcast read-back missed build 14 (attempt 1/6); retrying in 5s...
Published appcast read-back missed build 14 (attempt 5/6); retrying in 5s...
Error: published appcast does not contain build 14.
```

时间线（取自该 step 日志）：

- 14:30:20 `Build complete!`；14:30:31 `LC_BUILD_VERSION` 与 `codesign` 校验通过（两架构 `minos 15.0, sdk 26.0`）；
- 14:30:52 `gh release create v1.3.1` 成功，DMG `StatusTrio-1.3.1.dmg`（4 243 505 字节）与 sha256 随即成为 Release 资产；
- 14:30:52 appcast 经 Contents API `PUT` 成功提交（main 上的 `3979dc4`）；
- 14:30:55–14:31:24 回读 `appcast.xml?ref=main` 连续 6 次（间隔 5 秒，约 30 秒）仍读到旧内容，`exit 1`，整个 run 标红。

根因：**判据选错了实体，而这个滞后没有可测上界。** 上一条记录把窗口定为 6×5 秒，
依据只是"2 秒不够"这一个数据点；本次实测把上界推高了一个量级——写入后 30 秒仍读到旧 blob，
而此刻 `git/ref/heads/main` 已经是 `3979dc4`，约 5 分钟后 `contents` 读取才一致。所以再猜一个
更长的秒数并不能消除假失败。写入本身是同步的：`PUT` 的响应里就带着它创建的那个 commit，
而当时那行命令把响应丢给了 `/dev/null`。

修复：`scripts/release.sh` 的回读不再丢弃 `PUT` 响应，取其中的 `commit.sha`，判据改为
**git 层求证**——`git/ref/heads/<branch>` 指向该 commit 即视为已发布；`contents` 读取降级为
二次确认（仅在 `PUT` 未报告 commit 时依赖它），窗口放宽到 24×10 秒。错误文案未变，
`docs/superpowers/plans/2026-09-20-preflight-validator-and-appcast-sync.md` 中引用它的断言不受影响。

验证：

- **发布四项核验（该 run 实际结果）**：`Run tests` 成功；DMG `StatusTrio-1.3.1.dmg`（4 243 505 字节）
  与 sha256 已在 Release 上；Release [v1.3.1](https://github.com/lingyired/status-trio/releases/tag/v1.3.1)
  已发布且非 draft/prerelease，tag 指向 `568ac50`；appcast 提交 `3979dc4` 已在 main，Sparkle 源已含 build 14。
- **远端 appcast 条目**：12 titles + 12 descriptions、`en` 首位、阿拉伯语带 `div dir="rtl"`、
  真实 `sparkle:edSignature`、`length` 与 Release 资产一致、无残留 `%VERSION%/%BUILD%` 占位符。
- **桩测**（真实代码块 + 桩 `gh`）：用 `awk` 从 `scripts/release.sh` 逐字抽出回读段执行，
  三种场景全绿——① `git/ref` 首次即指向 `PUT` 的 commit：退出 0，且**完全不读 contents**；
  ② `git/ref` 滞留、contents 第 3 次追上：退出 0，读 3 次；③ 两者都滞留：读 3 次后打印原错误
  信息并以 1 退出。
- **`--input -` 与 `--jq` 共存**：本次新引入的组合在 gh 2.96.0 上实测可用（对 `POST /markdown`
  传 body 并用 `--jq` 处理响应，jq 报的是响应解析错误而非参数冲突），该接口零副作用。
- `bash -n scripts/release.sh` 通过。本次改动只有 shell 与 Markdown，未触碰 Swift 代码，按规则
  无需新的工具链预检。**同一 tag 不允许复跑**（`release.sh` 在 Release 已存在时拒绝），所以新判据
  只能由下一次正式发布行使。

## 35842269867：1.3.2 正式发布，新回读判据首次即命中（兑现上一条的留话）

上一条结尾那句「新判据只能由下一次正式发布行使」在 1.3.2 兑现了。run
[`35842269867`](https://github.com/lingyired/status-trio/actions/runs/35842269867)
（`version=1.3.2`、`build=15`、`publish=true`、`ref=main`）5m6s 全绿：

- `Validate appcast notes`：12/12 语言、`12 titles and 12 descriptions, en first`；
- `Run tests`：XCTest **760 个（6 skipped）、0 failures**，swift-testing **247 个 / 35 suites**，0 failures；
- `Build, sign, notarize, and publish`：`LC_BUILD_VERSION check passed`（两架构 `minos 15.0, sdk 26.0`），
  `codesign` 报 `valid on disk` / `satisfies its Designated Requirement`；
- **回读判据首次即命中 git 层**：`Creating GitHub Release v1.3.2...`（09:24:41）到
  `Published …StatusTrio-1.3.2.dmg`（09:24:46）只隔 5 秒，日志里**没有任何 `retrying in` 行**——
  即上一条设计的桩测场景①（`git/ref` 首次就指向 `PUT` 的 commit，完全不读 `contents`）在真实发布上成立，
  1.3.1 那种「写入成功却判失败」的假失败没有复现。

发布四项核验：Release [v1.3.2](https://github.com/lingyired/status-trio/releases/tag/v1.3.2)
已发布且非 draft/prerelease，tag 指向 `2055908`；DMG 4 317 802 字节与 sha256 均已附加；appcast
提交 `5cd8c7e` 已在 main，Sparkle 源条目为 12 titles + 12 descriptions、`en` 首位、阿拉伯语带
`div dir="rtl"`、真实 `edSignature`（88 字符）、`length` 与 Release 资产一致、无残留占位符。

一处读路径滞后值得记住：`gh api repos/…/releases/tags/v1.3.2` 的 `assets` 字段在发布后数分钟内仍返回
空数组（`/releases/tags/…/assets` 甚至 404），而同一时刻 Release 页面的 `expanded_assets` 已列出两个
资产、`releases/download/v1.3.2/StatusTrio-1.3.2.dmg` 直链返回 200。**核对资产不要只看 `assets` 字段**，
用页面或直链交叉验证。
