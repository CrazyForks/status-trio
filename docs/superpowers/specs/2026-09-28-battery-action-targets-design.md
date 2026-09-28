# 电池面板动作目标设计

## 目标与范围

用户希望把电池面板中固定的「打开电池设置」动作改为可选目标：macOS 电池设置、已安装的 AlDente 或 BatFi、用户选取的任意 `.app`，或用户填写的 URL。既有用户和未配置用户继续打开 macOS 电池设置。动作只负责打开目标，不控制第三方应用的充电行为。

成功标准：选择能跨重启保存；设置页能发现已安装的工具；电池详情按钮和摘要齿轮执行同一目标，文案及无障碍名称反映目标；目标消失、URL 无效或打开失败时回退到原有的 `batterySettingsURLs`。不新增后台轮询、系统权限、私有 API、进程调用或安装入口。

用户提供的 `docs/superpowers/plans/2026-09-28-battery-action-targets.md` 是待修订的实施草案。本设计以已确认的产品目标为准，补齐该草案中启动失败、已卸载选项和 deep link 顺序的缺口。

## 选择与设置界面

- `SettingsStore` 保存一个当前 `BatteryActionTarget`。选项包括系统设置、已知工具、自定义应用、自定义 URL；切换选项会替换上一个自定义目标，不额外保存历史选择。
- 电池设置页在现有外观设置下方增加独立的「电池动作」组。已知工具只在检测到安装时提供新选择；如果当前已选择的工具后来被卸载，它仍显示为当前选项并标注「未安装」，不悄悄改写偏好。重新安装后原选择立即恢复可用。
- 自定义应用通过 `NSOpenPanel` 选择 `.app`，记录显示名、Bundle ID 和备用路径。取消面板不改变选择。若已选应用后来无法定位，设置页保留其名称并标注「未安装」。
- 自定义 URL 用文本行编辑；用户输入时不执行。允许任意可解析且含非空 scheme 的 URL，不设 scheme 白名单。空值或无效值显示非模态提示；点击面板动作时安全回退。选择另一目标后，先前的自定义 URL 不单独保留。
- 电池详情按钮、摘要齿轮的帮助文本与无障碍名称使用同一展示函数生成「打开电池设置」「打开 AlDente」「打开〈应用名〉」或「打开自定义链接」。长名称在现有 330 pt 面板内单行截断。文案覆盖现有 12 种本地化语言。

## 数据与职责

1. `BatteryActionTarget` 使用显式、稳定的 `Codable` discriminator；`SettingsStore` 在现有 `UserDefaults` 中以 `batteryActionTarget.v1` 保存 JSON `Data`。缺失、未知或损坏的数据解码为 `.systemSettings`，不建立第二套设置存储。
2. `KnownBatteryApps` 只记录工具名称、经核实的 Bundle ID 和可选的公开验证 deep link。本机安装包已核实 AlDente 的 `com.apphousekitchen.aldente-pro` 与 BatFi 的 `software.micropixels.BatFi`。旧版 AlDente ID 只有在实施时找到可靠依据后才纳入；首版不填猜测的 deep link。
3. `BatteryActionLauncher` 独占 `NSWorkspace` 和 Launch Services 调用，并通过可替换的操作接口接受测试注入。设置页可调用只读的按需可用性查询；SwiftUI 视图不自行查找或启动应用。`StatusBarController` 关闭 popover 后调用 launcher，且保留现有 `batterySettingsURLs` 为最终回退。

## 打开顺序与失败处理

- 系统目标直接使用原有电池设置路由。
- 已知工具先按目录中的 Bundle ID 确认安装，再尝试其**已验证**的 deep link；deep link 打开失败则启动已解析的应用。未安装时不尝试 deep link，直接回退到电池设置。
- 自定义应用先通过 Bundle ID 重新定位并启动；找不到或启动失败时，尝试仍存在的备用 `.app` 路径；两次都失败才回退到电池设置。同一 URL 不重复启动。
- 自定义 URL 通过统一校验后调用 `NSWorkspace.open`；校验或打开失败时回退到电池设置。
- 应用启动结果是异步的。launcher 必须等待成功或失败结果后再决定是否回退，并在主 actor 上触发最终设置路由；不把「已发出启动请求」视为成功。动作失败不在弹窗中显示阻塞式警告。

## 验证与发布边界

- 注入假 workspace，覆盖所有目标的成功、缺失、异步启动失败、备用路径、deep link 成败和最终回退；测试不依赖 CI 机器安装 AlDente 或 BatFi。覆盖 JSON 往返/损坏、已卸载选项仍可见、取消选取、URL 校验、12 种语言的键值一致性，以及英文和简体中文的长名称布局。
- 本机核对 AlDente、BatFi 检测与启动，以及任意 `.app` 和已安装 URL scheme 的打开。移动或删除应用的回退路径可用注入测试验证；若未在本机实际执行，验证记录须明确写出。不可把本地 Swift 6.4 通过等同于 CI 的 Swift 6.3.3 通过。
- 实施时补 `docs/battery-actions.md`，并为目标发布版本准备 12 种语言的 release notes。Swift 改动先运行 `swift test`、`swift build -c release`；涉及 `@MainActor` 和 SwiftUI 绑定，合并或发布前还需在项目的 Xcode 26.6 / Swift 6.3.3 release workflow 做 `publish=false` 预检。失败的 Actions run 按仓库规则记录到 `docs/swift-ci-compatibility.md`。不通过该预检就不发布。
