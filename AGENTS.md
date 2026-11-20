# Pumpkin 插件迁移指南

> 本指南供编程 Agent 将现有 Minecraft 插件迁移到 Pumpkin 时使用,并帮助使用者建立插件的安装、使用、数据迁移和维护文档。

## 准备工作：

- 分析 Pumpkin 项目当前的 Native 和 Wasm 插件接口，选择目标服务端实际支持的最新版本。记录 Pumpkin 的版本或提交、Minecraft 版本、插件 SDK 版本和构建方式。
  - **Wasm**： 优先使用 wasm32-wasip3，注意权限设置等[宿主构建特性](https://github.com/Pumpkin-MC/Pumpkin/blob/master/crates/pumpkin/Cargo.toml) · [Rust SDK 绑定](https://github.com/Pumpkin-MC/Pumpkin/blob/master/crates/pumpkin-plugin-api/src/lib.rs) · [WIT 定义](https://github.com/Pumpkin-MC/Pumpkin/blob/master/crates/pumpkin-plugin-wit)
  - **Native**： 只有 Wasm 无法实现大部分功能时才考虑 [Native 接口](https://github.com/Pumpkin-MC/Pumpkin/blob/master/crates/pumpkin-core/src/plugin/mod.rs)，并向使用者说明接口缺口与部署影响。为 Native 记录目标平台与的 `PLUGIN_API_VERSION`。[Native 接口版本](https://github.com/Pumpkin-MC/Pumpkin/blob/master/crates/pumpkin-core/src/plugin/mod.rs)

- 查阅与所选接口、语言和原插件平台相关的文档。文档示例与目标版本有出入时，以对应提交的接口定义、宿主实现和实际运行结果为准。
  - [Pumpkin Plugin Knowledge Base](https://book.vypal.me/)：查阅 Wasm 插件接口、版本差异和使用示例。
  - [Pumpkin 官方插件开发文档](https://docs.pumpkinmc.org/plugin-dev/introduction)：查阅各语言的开发入口、项目结构和构建方式。
  - [从 Bukkit 迁移至 Pumpkin](https://docs.pumpkinmc.org/plugin-dev/migrating-from-bukkit/)：查阅命令、事件、GUI、配置与数据存储的迁移示例。
  - 其他语言的官方插件示例：[C](https://github.com/Pumpkin-MC/pumpkin-api-c)、[C#](https://github.com/Pumpkin-MC/pumpkin-api-cs)、[D](https://github.com/Pumpkin-MC/pumpkin-api-d)、[GO](https://github.com/Pumpkin-MC/pumpkin-api-go)、[Kotlin](https://github.com/Pumpkin-MC/pumpkin-api-kt)、[Python](https://github.com/Pumpkin-MC/pumpkin-api-py)、[Rust](https://github.com/Pumpkin-MC/pumpkin-plugin-examples)、[TypeScript](https://github.com/Pumpkin-MC/pumpkin-api-ts)、[Zig](https://github.com/Pumpkin-MC/pumpkin-api-zig)、[WIT](https://github.com/Pumpkin-MC/pumpkin-plugin-wit)

- 分析原插件的项目类型和详细功能。先确认它运行在 [Pumpkin](https://github.com/Pumpkin-MC/Pumpkin) 服务端、[Vine](https://github.com/Pumpkin-MC/Vine) 代理端还是同时两端，再从入口、命令、事件监听器和数据读写代码追踪实际行为。列出核心功能、权限节点、前置依赖、配置项、数据文件和数据库类型。关键行为含糊时，在原平台运行一次，记录操作步骤与结果，供迁移后对照。

## 规划迁移：

为每项功能写出原有行为、需要使用的 Pumpkin 接口、所需依赖和测试方法。先迁移一个核心功能，从命令或事件入口开始直到玩家使用。涉及数据库时需要核对数据库兼容性。




**最终确定使用哪些第三方插件前，须询问 Agent 使用者** 并说明每项依赖解决什么问题、是否必需，以及缺失时会影响哪些功能。找不到合适替代品时，简单且独立的功能可在许可允许的范围内嵌入插件；复杂功能应先查阅文档，再与使用者确定方案。

| 原插件的需求 | 候选插件与核对重点 |
| --- | --- |
| 基础命令 | 核对命令名、参数和权限。[VEssentials](https://market.pumpkinmc.org/plugin/IFGGQmCS) |
| 共享余额 | 核对账户标识及扣款、退款接口。[PVault](https://github.com/vyPal/PVault) |
| 权限与权限组 | 核对权限节点、默认值和组继承。[GourdPerms](https://market.pumpkinmc.org/plugin/9WfbQ2h0) |
| 随机安全传送 | 核对目标世界、安全位置条件和失败结果。[GourdRTP](https://market.pumpkinmc.org/plugin/56jjI1s0) |
| 占位符 | 核对注册与解析接口和可用的玩家上下文。[PumpkinPIE](https://github.com/Rennex07/PumpkinPIE) |
| 世界编辑 | 按需核对选区接口和结构文件格式。[WorldEdit for Pumpkin](https://github.com/PumboMC/WorldEditPumpkin) |
| 持久化文字全息图 | 核对创建、更新和重启后的恢复方式。[SimpleHolograms](https://github.com/Rennex07/SimpleHolograms) |

更多候选插件可到 [Pumpkin Market](https://market.pumpkinmc.org/) 搜索。

## 开始迁移：

正式开始前，须遵守以下约定。遇到会影响核心功能、数据兼容或部署方式的问题时，向 Agent 使用者说明原因和可选建议，再确定如何处理，不要自作主张。

- **结构与生命周期。** 按目标语言的惯例和 Pumpkin 的生命周期组织代码，按需拆分命令、事件、业务逻辑、配置、存储和第三方集成。随插件加载和卸载注册、清理定时任务与监听器。为每个函数编写文档，写明用途，并按需说明参数、返回值、副作用和失败结果。复杂分支可就近注释，例如说明事件取消后为何要退款。

- **测试与工具。** 单元测试优先使用插件的实现语言。Rust 插件可用 `#[test]` 覆盖余额计算、冷却判定和旧记录解析，将适用的检查接入项目。用 `rustfmt` 检查格式、Clippy 检查代码、`typos-cli` 检查拼写、`cargo-machete` 排查闲置依赖。调查内存分配时，可在支持的本地目标上选用 `cargo-heaptrack`。

- **性能与游戏 tick。** 将慢查询和大文件读写安排在宿主支持的异步接口或后台任务中，优化内存使用，减少造成的性能浪费。能否使用多线程取决于目标运行时。并行处理时仍须保持事件与存储操作的顺序，尤其要避免两次并发操作重复扣款。优化前后用同一份数据比较耗时和内存占用。

- **插件间 API。** 功能有明确的联动需求时，可通过目标宿主支持的接口供其他插件调用，记录接口版本、参数、返回值和失败条件。例如，提供传送点查询时，说明玩家 UUID、传送点名称和世界标识如何传递，以及查询无结果时调用方会收到什么。

- **命令、事件与网络。** 优先使用 Pumpkin 的命令、传送、物品和 GUI 等高层 API，确需收发数据包时使用 Pumpkin 自带的网络接口。保留命令名、别名、参数补全、权限检查及控制台支持。按原插件的事件顺序处理取消与失败，特别核对余额、物品和冷却状态。

- **配置与数据。** 新插件使用所属语言的常用配置（如 Rust 可使用 TOML），为有变化的配置项列出旧键、新键、单位和填写示例。按内容区分设置与玩家数据。例如，传送冷却时长属于设置，旧 `config.yml` 内的传送点、领地和余额属于待迁移数据。为新插件的玩家数据选择新存储时优先使用 SQLite，沿用旧库时遵循原插件的后端和结构。

- **玩家语言。** 为插件使用独立的翻译命名空间，优先用 Pumpkin 的翻译和文本接口提供 `en_us` 与 `zh_cn`。命令帮助、成功和错误提示按玩家客户端语言显示，为控制台及缺失译文指定回退语言。用含玩家名、金额等替换参数的消息核对显示效果。[v0.1 翻译接口](https://github.com/Pumpkin-MC/Pumpkin/blob/master/crates/pumpkin-plugin-wit/v0.1/i18n.wit) · [v0.2 翻译接口](https://github.com/Pumpkin-MC/Pumpkin/blob/master/crates/pumpkin-plugin-wit/v0.2/i18n.wit)

- **Web UI。** 原插件附带前端时，优先复用原前端，让迁移后的后端继续支持页面使用的请求路径、数据字段和身份验证方式。将前端和插件本体分开打包发布，并标明配套版本。例如，管理页面允许编辑传送点时，用原页面打开一个旧传送点，保存新坐标，刷新后再到游戏中传送并核对落点。

- **接口缺口。** 若缺口影响核心功能、数据兼容或部署方式，列出受影响的操作及可选方案，与使用者确认后再调整范围。可以延期的非核心功能应保留关联数据，并记录缺少的接口和当前可用的替代操作。

## 数据兼容：

为每种承诺支持的格式准备旧插件生成的样本或脱敏副本。记录旧插件版本、数据位置、后端（如 SQLite、MySQL、PostgreSQL）、文件格式（如 YAML、JSON、NBT）、表前缀、结构版本和关键字段。逐项核对玩家 UUID、世界标识、坐标与朝向、金额精度、时间单位及记录间的引用。遇到未知版本、世界或身份，保留原始值，并在报告中标出来源表名或文件名、记录标识和失败原因，供服主定位。

先与使用者确定切换后哪些服务端还要读写数据，再选择兼容方式。若新旧插件共用原库，保留旧插件依赖的字段含义和约束。例如，给旧表新增必填列时，要验证旧插件仍能按原语句插入一条记录，切记数据库要对应原版插件，并保证新插件和原版插件都能够正常接入和读写。

| 使用场景 | 需要证明的结果 |
| --- | --- |
| 新旧插件继续使用原库 | 在同一份数据库副本上，用旧端写入，用新端读取、修改并重启复读，再用旧端读回修改值。若允许多服同时写入，还应验证同一记录发生并发更新时的结果。 |
| 一次性无损导入，随后使用新存储 | 在临时目标中导入，核对记录数、关键引用及适用的汇总值（如余额总额）。模拟中断并重试，再完整运行一次，核对是否重复建档、增加余额或发放物品。 |

### 演练、切换与回滚

1. 在独立环境演练，从备份恢复一份可供旧插件读取的副本。记录备份对应的时间和数据版本。
2. 正式操作前让相关服务停写，或取得一致性快照并明确如何补入快照后的写入。用事务或临时目标执行写入，记录成功、冲突、失败的数量和原因。
3. **读取旧记录 → 修改 → 重启服务端 → 再次读取。** 例如，用原玩家身份列出中文传送点“矿场”，传送后核对世界、坐标和朝向。修改传送点的位置，重启，再次传送并核对新位置。承诺旧库双向兼容时，再用旧插件传送到修改后的位置。
4. 在回滚说明中分别写清如何恢复旧服务、如何处理切换后的新增或修改记录。例如，若约定保留切换后新建的传送点，应在副本上演练如何带回这些记录，再用旧端按名称查找、传送并核对落点。

## 验证阶段：

- **优先本地环境。** 对原平台为 Paper 的插件，向使用者确认本地 Paper、Pumpkin 测试服目录，以及 Pumpkin 版本和已启用的 API。其他原平台使用相应的测试环境。需要真实客户端时，确认其安装位置。使用者已提供的目录和版本可直接复用。只有缺少或未提供相应测试环境时，才在本地搭建所需服务端。

- **验证实际文件。** 从干净的项目环境构建，将文件和已确认的依赖加载到独立测试目录，检查启动、运行、卸载与关闭日志。分别验证全新安装和旧版本迁移。若支持 Wasm、Native 或多个系统平台，按文件与平台分别记录结果。

- **检查失败路径。** 逐项验证正常操作、参数错误、权限不足、依赖缺失和执行失败。记录玩家提示、实际状态及持久化结果。例如，用无权限玩家访问“矿场”，同时检查拒绝提示、位置和余额。若支持热重载，重载后执行一次命令或事件，检查重复监听、重复扣款和数据丢失。

- **玩家可见行为。** 使用英语和简体中文客户端触发同一条消息，核对语言及替换参数。通过真实客户端操作 GUI，检查全息图、粒子、声音等实际效果。如果插件同时面向 Java 版和基岩版，分别在两端验证。

- **可复现的记录。** 写出环境、初始数据、命令或操作、预期与实际结果。尚未实测的版本、平台和功能标为“未验证”，并写明下一位测试者可执行的具体步骤。

## 建立文档：

尽量以符合人类的语言和日常语气编写文档，一些权限和命令说明尽量简单明了。

| 位置 | 读者应能据此完成的操作 |
| --- | --- |
| 插件项目的 `README.md` | 插件图标，了解用途、支持的 Pumpkin 版本、Wasm 或 Native 产物和依赖版本。按说明将插件放入目标位置、首次启动，并用一个命令或操作核对预期结果。 |
| `doc/` 下的使用说明 | 查询命令、别名、参数、权限节点及默认权限，照示例执行。知道各配置项的用途、默认值、生效条件，以及是否需要重启。 |
| 迁移与回滚说明，篇幅较长时单列 `docs/TMIGRATION.md` | 确认支持的旧版本、数据库及文件格式，区分手动重填的配置和自动导入的数据，依次完成备份、演练、切换、核验和恢复，并能找到冲突记录。 |
| 功能对照与构建验证记录 | 区分已实现、行为有差异、已延期及未验证的功能，说明影响与可用的替代操作。记录源码提交、工具链、SDK、构建特性、测试环境和结果。未完成事项可列在 `docs/TODO.md`，写明原因。 |

小型插件可将上述说明合并到一份 README，以服主能找到安装、迁移和恢复步骤为准。

## 构建流程：

推送插件项目到 GitHub 前，至少准备 `Releases` 和 `Nightly` 两个可执行的构建入口。两者可以共享编译与打包脚本。分别验证两条流程生成的文件和插件版本号，并在目标 Pumpkin 上加载插件。
每次构建都要附上对应的提交更新记录，让服主能查到这一版改了什么。对 Rust 的 `wasm32-wasip3` 和 Pumpkin Wasm API `0.2.0` 项目，可复用仓库模板，按目标项目配置 Cargo 包名、发布文件名和插件元数据中的版本号。[构建与发布模板](templates/wasm-plugin/README.md)

| 入口 | 触发与产物 |
| --- | --- |
| `Nightly` | 推送提交后自动运行。仓库模板对任一分支的每次推送构建一次，以该次推送的最后一个提交发布 GitHub 预发布版。 |
| `Releases` | 由使用者手动发布，启用常规发布优化。仓库模板要求在默认分支输入正式版本号，如 `1.2.3`，将构建结果发布到 `v1.2.3`。 |
| Pumpkin Market | 如需上架或更新，须由使用者确认，并使用对应 GitHub 正式版的原始附件。用模板时，先在开发者后台建立条目，将数字 ID 存入 GitHub Actions 变量 `PUMPKIN_MARKET_PLUGIN_ID`，将令牌存入 Actions 密钥 `PUMPKIN_MARKET_TOKEN`，再由使用者在 `Releases` 中勾选商店上传。[Pumpkin Market 开发者后台](https://market.pumpkinmc.org/dashboard/plugins) |
