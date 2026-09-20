# Class A 计划集 —— 进度、裁决与续跑手册

## 更新（2026-09-20，R-02 合并后）

**R-02（Wi-Fi 扫描节奏）已全部完成并合并**（`536d8d4`，最终非发布预检 [`35528756095`](https://github.com/lingyired/status-trio/actions/runs/35528756095) `build=20`：683 XCTest（6 跳过，0 失败）+ 168 Swift Testing，两切片 `minos 15.0 / sdk 26.0`，未发布）。

当前状态：**已合并 4 个计划 / 27 个 task**（R-18、R-03、R-01、R-02），**12 个计划 / 61 个 task 未开始**，class C 四个计划仍冻结。
下一个建议做 **R-04（图标预览渲染，6 task）**。

R-02 的残留项（已裁定，不在本计划内修，供后续 triage）：

1. **无网卡恢复上限无法区分"没有 Wi-Fi 硬件"与"有硬件但接口读卡在 nil"**：后者在旧代码里 30–60 秒自愈，现在 3 次重建后要等睡眠/唤醒或连接失效。若要恢复慢速自愈，需要一个更慢的上限后兜底（设计改动）。
2. **返回行的接线没有测试钉住**（`StatusPopoverView` 的 Wi-Fi `onBack` 里那行 `store.closeWiFiDetails()`）：修者证明了当前测试环境**无法**驱动 SwiftUI 按钮动作（`NSApp.activationPolicy() == .prohibited`、无 key window、合成事件到不了 SwiftUI、托管视图只暴露不透明 `AXGroup`、`AXIsProcessTrusted()` 为 false），因此任何测试都只能重复覆盖 store 方法；真正的钉住需要另建 UI 测试 target，属范围外。
3. Release notes 的措辞与行为一致；T5 的 brief 里 `--ref`/`build` 陈旧（记录为 brief 缺陷）。

**发布前必须补的三项实测**（都不影响合并，但发布说明已经对外宣称效果）：R-03 功耗采样、R-01 spawn 次数、R-02 扫描次数。三者都在 `docs/swift-ci-compatibility.md` 里标为 `⏳`，并写明命令；**文档里没有任何推断出来的数字**。

> **本文件是暂停点（2026-09-20）的交接文档。** 由执行 agent 在 owner 要求"收尾后暂停，把剩下的写入文档"时写下。
> 配套文件：计划集索引（spec）`docs/superpowers/plans/2026-09-20-review-findings-index.md`；每个计划自己的 ledger 在
> `.superpowers/sdd/<plan>/progress.md`（该目录被 gitignore，只在工作树里）。

---

## 1. 一句话状态

非冻结计划 **16 个 / 86 个 task**：**3 个计划 / 20 个 task 已合并进 `main`**，**1 个计划（R-02）进行到 1/5**
（已提交、未合并），**12 个计划 / 65 个 task 未开始**。class C 四个计划按 owner 指示完全冻结。
`main` 领先 `origin/main` **44 个提交且未推送**（owner 选择本地合并）。

---

## 2. 已合并的计划（3 个，均已通过各自验收）

| 计划 | 内容 | 最终非发布预检 | 测试 |
| --- | --- | --- | --- |
| **R-18** 方法引用合规 | 把 **17 处** actor-isolated 方法引用改为显式闭包（计划只列了 11 处）；新增 `scripts/check-forbidden-patterns.sh` 守卫并在 `swift test` 内强制执行（脚本缺失时 fail closed） | [`35496776064`](https://github.com/lingyired/status-trio/actions/runs/35496776064) `build=14` | 624 XCTest + 163 Swift Testing |
| **R-03** 轮询调度 | 兜底轮询加 `interval/5` tolerance、默认 5→15 秒（范围仍 5...60）、隐藏时 Wi-Fi/音量降到每第 4 个 tick、显示器睡眠时跳过（**有界自愈**：连跳 20 次后照常刷新）、`liveVolume` 去重 | [`35514169366`](https://github.com/lingyired/status-trio/actions/runs/35514169366) `build=16` | 637 XCTest + 163 Swift Testing |
| **R-01** 蓝牙轮询 | 每周期 `system_profiler` **2 → 1** 次；单次读锁 + 合并后续刷新；popover 门控的 30 秒兜底；IOBluetooth 连接/断开通知 + 750ms 防抖；完整 `deinit` 拆卸；**读队列退役 + 读看门狗**（缺一不可） | [`35521490583`](https://github.com/lingyired/status-trio/actions/runs/35521490583) `build=18` | 668 XCTest + 168 Swift Testing |

合并后 `main` 本地验证：守卫退出 0，全绿。三次合并都是快进，历史线性。

**每次预检都在 `docs/swift-ci-compatibility.md` 里留了完整记录**（run id、阶段、测试数、`minos 15.0 / sdk 26.0`、未发布声明）。

---

## 3. 进行中：R-02（Wi-Fi 扫描节奏）

分支 `fix/class-a-wifi`，**1/5 task**，提交 `8dfaf62`，**未合并**。

**已完成 T1**：新增 `WiFiNetworkScanning` 协议、可注入的 `scanWorker`/`now`/`minimumScanInterval`(30s)/`periodicRefreshSleep`，
并把 `refresh(nameAccess:)`（自动路径，间隔内复用缓存）与 `refreshNow(nameAccess:)`（显式路径，总是扫描）分开。

**T2–T5 未开始**，且有三项**必须带过去的义务**：

1. **T2 必须把三个用户主动触发的路径改走 `refreshNow`**：`WiFiNetworkController.swift:497`（`setPower` 完成）、`:640`（关联完成）、
   `WiFiNetworkListView.swift:66`（刷新按钮）。在改之前，30 秒窗口内切换无线电开关或加入网络**不会触发扫描**；
   对 `setPower` 这是用户可见的——`state` 已变 `.ready` 但旧 `networks` 还在，页面会列出已关闭的无线电看不到的网络。
   （计划正是这样安排的：`wifi-scan-cadence.md:463/509/521/531/557`，且 T2 的 RED 依赖它们仍被 floor。）
2. **`:449-452` 的注释声称这些路径已经调用 `refreshNow`**——在该提交上不成立，T2 要同时改代码或注释。
3. **T3 建议顺带修一个既有冻结 bug**：若扫描进行中 `deactivate()`，完成回调被 `!isActive` 丢弃，`state` 永久停在 `.scanning`，
   之后所有 `refresh`/`refreshNow`（含状态 yield 路径）都被 `!state.isScanning` 挡住，页面刷新按钮禁用。既有问题（不是 `8dfaf62` 引入），
   T3 新增的 `closeWiFiDetails()` 是清理 `state` 与 `lastScanStartedAt` 的自然位置。

---

## 4. 未开始的计划（12 个 / 65 个 task）

| 计划 | task | 内容 | 注意 |
| --- | --- | --- | --- |
| **R-04** 图标预览渲染 | 6 | 设置面板预览在 SwiftUI `body` 里做 512² 栅格化（一次拖动 ≈84 次）；改为按像素尺寸缓存 | 计划写于 `AppIconController` 归属变更前，实施前先读文件 |
| **R-05** 外观轮询 | 3 | 2 秒外观轮询无 tolerance（4.3 万次精确唤醒/天）→ 可注入定时器 + 2→4→8→10s 退避 | **T16 先于它落地**（共享测试文件） |
| **R-06** 音频主线程 IO | 4 | 主线程 CoreAudio HAL IPC（`reconcile()`）阻塞菜单栏且绕过 ReadWatchdog；同时修 `VolumeMonitor`/`WiFiMonitor` 的 `deinit` 线程亲和 | 与 R-02 分函数共享 `WiFiMonitor.swift`，**不要同时改** |
| **R-07** 菜单栏渲染 key | 6 | 渲染 key 量化 + **VoiceOver 值独立门控**（否则会造成无障碍信息不更新） | **R-18 已合并**，现在可以直接做 |
| **R-14** 电池回调拆卸调查 | 5 | `BatteryMonitor` 回调上下文疑似 use-after-free；含 TSan 步骤与"无法复现则不改代码"的决策行 | 用新测试文件，不动 `BatteryMonitorTests.swift` |
| **R-15** 测试门禁 | 7 | 新增 PR + main push 的 `swift test` 门禁（复用 release 的 Xcode 26.6 选择方式） | 纯 CI，用户不可见；建议与 R-20 一起做 |
| **R-16** 固定睡眠测试 | 5 | 固定 900ms sleep 对抗 0.5s debounce（含一个空断言）→ 确定性等待；`AppIconController` 暴露可注入 debounce 间隔 | **R-05 依赖它** |
| **R-17** 预检校验器 + appcast 同步 | 5 | 缺说明时静默跳过（incident `35375443023`）改为硬失败；给已发布/已提交 appcast 加同步契约 | ⚠️ **与冻结的 R-08 共享 `scripts/release.sh`**：R-08 冻结期间只能做与 feed 签名无关的部分，需要 owner 决定 |
| **R-19** 图标 parity + 生命周期测试 | 5 | 菜单栏↔Dock parity 表驱动矩阵、生命周期/泄漏测试、coalescer.cancel 覆盖 | 需在 R-04/R-05/R-16 之后（共享文件与 seam） |
| **R-20** 编译警告清理 | 4 | 7 处告警（4 类）：`String(cString:)` + 4 处 `weak var`；明确不放松 `AGENTS.md` 的 `weak let` 规则 | 其中 2 处 Keychain 废弃告警属于 **R-12** |
| **R-12** Keychain 加固（class B） | 6 | 保护等级未生效、废弃 API、系统 keychain 回退零测试；引入可注入 seam + **迁移** + 16 项测试 | 🔶 **涉及用户已保存的 Wi-Fi 密码**：迁移必须 write→read-back→再删除，保留 legacy 回退 |
| **R-13** 单实例 + 剪贴板（class B） | 5 | 锁加 `O_NOFOLLOW`/`fstat` 并让失败可见；剪贴板标记 transient/concealed；用 LockProbe 取代静默跳过的 python3 依赖 | 🔶 用户可见（新增失败提示）；与 R-01 曾共享 `AppDelegate.swift`（R-01 已合并） |

---

## 5. 冻结的 class C（4 个 / 29 个 task，按 owner 指示一行未动）

| 计划 | task | 为什么冻结 |
| --- | --- | --- |
| **R-08** 签名更新 feed | 6 | 会改变更新契约、**永久固定 EdDSA 私钥**；且必须与 `SUVerifyUpdateBeforeExtraction` 同批落地，否则 `SPUUpdater` 启动失败。需要灰度 + 回滚预案 |
| **R-09** 镜像回退策略 | 6 | 去掉/收紧第三方镜像会影响受限网络用户**能否更新**——需要 owner 先权衡可用性 |
| **R-10** 发布链路加固 | 9 | 需要 owner 在仓库设置里操作（protected environment、tag protection） |
| **R-11** 签名硬化 | 8 | 没有开发者账号；且实测**在 ad-hoc 上强行加 `--options runtime` 会让 app 起不来**（Sparkle 无法加载），现状是正确选择 |

---

## 6. Owner 待办（两件，都不阻塞合并，但**阻塞发布 1.3.0**）

1. **R-03 改动后的功耗采样**（计划 Task 7 Step 4）。
2. **R-01 改动前后的 spawn 次数采样**（面板关闭时应为 **0** 次；蓝牙界面可见时约每 30 秒一次）。

两项都需要用 dev bundle（`scripts/build-worktree.sh release no-open` 会派生独立 bundle id，不覆盖已安装版本），
命令与注意事项已写在 `docs/swift-ci-compatibility.md` 的对应小节里（含"先退出正式版，保证只有一个 StatusTriO 进程"这一步，
否则 `top -pid` 会因两个 PID 报错）。**文档里没有记录任何推断出来的数字。**

3. **是否推送 `main`**：目前领先 `origin/main` 44 个提交，全部是本地合并的成果。推不推由 owner 决定。

---

## 7. 如何续跑

```bash
# 1. 进入工作树（复用同一个目录，避免每个计划重建 1.5 GB 构建缓存）
cd /Users/lingsmbp/Documents/aiwork/status-trio/.worktrees/class-a-hardening
git status --short              # 应为空
git log --oneline -1            # 应为 8dfaf62（R-02 T1）
git branch --show-current       # fix/class-a-wifi

# 2. 读 R-02 的 ledger（含 3 项 carry-forward 义务）
cat .superpowers/sdd/2026-09-20-wifi-scan-cadence/progress.md

# 3. 继续 R-02 的 T2（brief 由脚本从计划里抽取，永远是单一事实来源）
bash .agents/skills/subagent-driven-development/scripts/task-brief \
  docs/superpowers/plans/2026-09-20-wifi-scan-cadence.md 2
# → 按 subagent-driven-development 的流程：实现者 → 任务评审 → 修复循环 → 完成

# 4. R-02 全部 5 个 task 完成后：跑非发布预检
git push -u origin fix/class-a-wifi
gh workflow run release.yml --repo lingyired/status-trio --ref fix/class-a-wifi \
  -f version=1.3.0 -f build=19 -f publish=false
gh run watch <run-id> --repo lingyired/status-trio --exit-status

# 5. 合并（先断言当前分支；不要 checkout main，会打断 owner 的工作分支）
#    注意：本交接文档本身已提交到 main（b186190），因此 main 已**不是** fix/class-a-wifi 的祖先。
#    续跑时先把分支同步到 main，再合并：
#      git rebase main        # 或 git merge main
#    之后 main 才能再次快进：
cd /Users/lingsmbp/Documents/aiwork/status-trio
[ "$(git branch --show-current)" = "main" ] && git merge --ff-only fix/class-a-wifi \
  || { git merge-base --is-ancestor main fix/class-a-wifi && git branch -f main fix/class-a-wifi; }
```

**每个新计划的准备工作**（照 R-01/R-02 的先例）：

1. `bash .agents/skills/subagent-driven-development/scripts/sdd-workspace <plan>` 建 ledger；
2. 查漂移：`git log --oneline 13cdbbc..main -- <files>`，**行号漂移时按符号定位，不按行号**；
3. 写预检扫描表（任务间共享文件、接口的生产/消费关系、任务自身是否自洽）+ 裁决；
4. 一次只开一个实现者；每个 task 都要过任务评审；修复循环最多 5 轮；终审后**一个**修复 wave + 一次定向复审。

---

## 8. 我在 owner 名下做的裁决（按计划，含代价）

**R-18（已合并）**
1. 偏离计划的字面正则（它匹配不到 8 个真实站点中的任何一个），把验收绑到"检出 11 处、零误报"。
2. 采用 `{ self.handle…() }` 覆盖计划里编译不过的写法。
3. 守卫的结构性盲点（带参数引用、非参数位置、非家族标签）记为**文档化非目标**，不做猜测式检测。
4. 覆盖计划强制的 `XCTSkipUnless`：守卫脚本缺失时**硬失败**而非绿色跳过。
5. 分支名用 `fix/class-a-hardening` 而非计划里的另一个名字。
6. **补齐 6 处漏检写法 + 加宽守卫**（而不是收窄分支的声明）——代价是多一轮预检。
7. 收紧整文件级的"转发闭包"豁免。
8. `Tests/` 暂不纳入扫描根，写进 Known limits。
9. 两条守卫假阳性路径记录为残留项（点号转发闭包、省略外部标签的闭包参数），当前都不触发。

**R-03（已合并）**
1. 覆盖 brief：`isDisplayAsleep` 只由两个唤醒通知清除 → 加**有界自愈**（连跳 20 次后照常刷新），避免"丢失一条通知 = 整个会话停摆"。
2. 批量 T5+T6 到一个 dispatch。
3. 预检用 `build=15`/`16`（计划写的 12 已被占用）。
4. 改动后功耗采样暂缓（需 dev bundle），写成"发布前必须完成"。

**R-01（已合并）**
1. 覆盖 T1 的 brief：电池读取会把"只是读到的"报告重新盖时间戳 → 只缓存真正抓取到的字节。
2. 把 T2 评审发现的"回调永不返回 → 读锁永久卡住"定为**计划缺口**，亲手补成新 Task 6（退役读队列 + 看门狗），因为**只加看门狗无效**。
3. 把 T3 评审的 view-token 外溢问题写成 T5 的必做 rider（门控必须以 popover claim 为准）。
4. 把 T4 评审的两条 Minor（`defer` 清掉新任务引用、新编译警告）提升为 T4 的必做 rider。
5. 批准改动"第四个文件"（两处 token 字面量）——必要、最小、零断言改动。
6. 接受 view token 变为 inert（评审证明它们在改动前就从未真正收窄过）。
7. 终审的两个 Important → 一个修复 wave：**注册泄漏**（断开时不 `unregister()`）+ 六项小修。
8. 实测 spawn 次数记为 owner 待办，**不编数字**。

**R-02（进行中）**
1. 行号漂移按符号定位（`SystemStatusStore` 已漂移约 9 个提交的量）。
2. T3 必须与 R-01 的 Bluetooth claim、R-03 的 stride/asleep 门控**共存**，不得互相干扰。
3. 保留权限契约与 `docs/wifi-status-responsiveness.md` 的响应性工作（CoreWLAN 读仍在主 actor 之外 + 读看门狗）。

---

## 9. 工程约定（续跑时必须遵守）

- **工具链**：CI 验收环境是 `macos-26` / Xcode 26.6 / Swift 6.3.3；本机 6.4 **不是**证明。
- **提交前**：`swift test` + `swift build -c release`；改动触及 actor isolation / `@MainActor` / `deinit` / SwiftUI binding / 泛型 / `Bundle.module` 时，
  **必须**跑一次非发布预检（`-f publish=false`）。
- **禁令**：`isolated deinit`、`weak let`、把 actor-isolated 方法当函数值传（现在由 `swift test` 里的守卫机械强制）、
  **`deinit` 里写 `MainActor.assumeIsolated`**（见索引 §3.4）。
- **失败记录**：每次 CI 失败都要追加到 `docs/swift-ci-compatibility.md`（run id、阶段、根因、修复、复验）。
- **菜单栏 ↔ Dock 图标 parity**：改图标渲染或图标设置必须两边同步 + 各自测试。
- **发布说明**：`release-notes/<version>/<lang>.md`，`en` + `zh-Hans` 必备，标题行含 `%VERSION%`/`%BUILD%`；只追加不重排。

**工作区事故与已加的守卫**：某次主检出被切到 owner 的 `feature/charging-effects` 分支，导致一次合并落到了
owner 的分支上（后来修复：`main` 快进到正确提交，owner 分支未受影响，未跟踪文件完好）。此后每次合并前都断言
"主检出当前分支 == `main`"，不满足时**不 checkout**，而是证明 `main` 是祖先后用 `git branch -f main` 快进。

**工作区现状**：worktree `.worktrees/class-a-hardening` 在 `fix/class-a-wifi`；owner 的
`feature/charging-effects` 分支与 `charging-effects-demo.html`、`docs/superpowers/specs/2026-09-20-bluetooth-battery-level-default-design.md`
两个未跟踪文件均未被本次工作触碰。
