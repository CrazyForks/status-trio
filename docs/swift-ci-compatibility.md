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

非发布预检 [`35448004467`](https://github.com/lingyired/status-trio/actions/runs/35448004467)
（`version=1.3.0`、`build=10`、`publish=false`）通过：602 个 XCTest（3 跳过）与 146 个
Swift Testing 全绿；通用 release 构建的两个切片都是 `minos 15.0 / sdk 26.0`，
`LC_BUILD_VERSION check passed`；DMG 打包与 artifact 上传成功，未发布 Release 或更新 appcast。
该次预检之后只有记录 CI 历史的 Markdown 提交。

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
