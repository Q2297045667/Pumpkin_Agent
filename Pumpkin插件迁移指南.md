> 这份指南写给负责插件迁移的 Agent。把插件移到 Pumpkin 后，给服主留一份说明，讲清楚怎么安装、怎么把旧服的数据带过来，出了问题又该怎么退回旧版。

### 准备工作：

- 先看原插件跑在服务端还是代理端，有没有两端配合的功能。从玩家常用的命令入手，顺着代码看它检查哪些权限、调用哪个前置、最后把数据写到哪里。源码里看不准的地方，可以在旧服试一遍，再决定先迁哪些功能。
- 选 API 时以服主实际运行的 Pumpkin 为准，用这个版本能加载的最新接口。记下 Pumpkin 提交、Minecraft 版本和插件 SDK，后面构建和排错都用得上。
  - 优先用 Wasm。先拿模板编译一个最小插件，在目标服上加载。插件要读文件或连接数据库的话，这时就试一下所需权限。[服务端构建特性](https://github.com/Pumpkin-MC/Pumpkin/blob/b6546d53851fdb5b4e5363ac388ce299c8ce13e2/crates/pumpkin/Cargo.toml#L29-L32) · [Rust SDK 绑定](https://github.com/Pumpkin-MC/Pumpkin/blob/b6546d53851fdb5b4e5363ac388ce299c8ce13e2/crates/pumpkin-plugin-api/src/lib.rs#L203-L209)
  - 只有 Wasm 做不了原插件的大部分功能时，才考虑 Native。把缺的接口和受影响的功能告诉使用者。选了 Native，就在服主使用的系统、架构和 Pumpkin 构建上试加载。[Native 接口](https://github.com/Pumpkin-MC/Pumpkin/blob/b6546d53851fdb5b4e5363ac388ce299c8ce13e2/crates/pumpkin-core/src/plugin/mod.rs#L37-L41)
- 查文档时可以从这几处开始。示例用的版本和目标服对不上，就回到相应提交看接口和实现。
  - [Pumpkin 官方插件开发文档](https://docs.pumpkinmc.org/plugin-dev/introduction)有各语言的建项和构建说明。[Pumpkin-MC](https://github.com/Pumpkin-MC) 和[官方插件示例](https://github.com/Pumpkin-MC/pumpkin-plugin-examples)可以用来找模板。
  - [Pumpkin Plugin Knowledge Base](https://book.vypal.me/) 讲 Wasm，查接口和版本差异时可以翻这里。
  - 原插件来自 Bukkit、Spigot 或 Paper，可以从[官方 Bukkit 迁移文档](https://docs.pumpkinmc.org/plugin-dev/migrating-from-bukkit/)找命令、事件和 GUI 的写法。
- 查看原插件究竟用了前置插件的哪几个功能。比如看到 Vault 依赖，要分清用的是余额、权限还是聊天。下面这些 Pumpkin 插件可以作为候选。
  - [VEssentials](https://market.pumpkinmc.org/plugin/IFGGQmCS)（基础命令）
  - [PVault](https://github.com/vyPal/PVault)（共享余额及经济接口。原插件用到的 Vault 权限和聊天接口要另找）
  - [GourdPerms](https://market.pumpkinmc.org/plugin/9WfbQ2h0)（权限和权限组）
  - [GourdRTP](https://market.pumpkinmc.org/plugin/56jjI1s0)（随机安全传送）
  - [PumpkinPIE | Placeholders for all](https://github.com/Rennex07/PumpkinPIE)（占位符）
  - [WorldEdit for Pumpkin](https://github.com/PumboMC/WorldEditPumpkin)（世界编辑。需要读取旧建筑文件时，用原文件试一次）
  - [SimpleHolograms](https://github.com/Rennex07/SimpleHolograms)（文字全息图）
- 还可以到 [Pumpkin Market](https://market.pumpkinmc.org/) 找。选定前置之前，先问使用者愿不愿意装，说明哪个功能会用到它、不装会怎样。找不到合适的前置时，简单功能可以自己实现。要复用原代码，先看许可证。复杂的功能，尤其是几个插件共用的钱包或权限组，先和使用者商量好由谁管理数据。

### 开始迁移：

- 沿用 Pumpkin 模板的写法，先挑一个常用功能，从命令或事件一直做到能在游戏里使用。命令处理、存储和第三方插件调用各自放在合适的模块里。碰到缺接口的次要功能，可以先放一放，留下它的旧数据，并在文档里写清影响。会卡住主要玩法的，先找使用者商量。
- 命令和网络数据包优先用 Pumpkin 自带的 API。原命令的别名、参数补全、权限节点和控制台用法也一起迁。传送、打开界面这类操作先找现成接口，确实需要直接发包时，再按目标协议确认发什么包、发给谁。
- 事件要看取消之后会发生什么。拿收费传送来说，在旧服试试余额不足、传送被取消时各会怎样。把扣款、退款和开始冷却的时机保留下来。定时任务和监听器要能随插件卸载清理，查数据库和读大文件时避免卡住游戏 tick。
- i18n 用 Pumpkin 的翻译和文本接口，先把英语 `en_us` 和简体中文 `zh_cn` 写全。翻译键放在插件自己的命名空间里。玩家按自己的语言看帮助和报错，控制台和缺少译文的消息用约定的默认语言。[Wasm i18n 接口](https://github.com/Pumpkin-MC/Pumpkin/blob/b6546d53851fdb5b4e5363ac388ce299c8ce13e2/crates/pumpkin-plugin-wit/v0.1/i18n.wit)
- 配置按新插件的用法重新设计，列出旧配置项在新版本里怎么填。玩家数据优先用 SQLite。留意旧 `config.yml` 里混存的传送点、领地或余额，这些都是服主已经在用的数据，换配置格式时也要带过来。

### 数据库兼容：

- 找一份旧插件生成的数据，记下插件版本、文件位置、数据库类型和表前缀。原插件如果同时支持 YAML、SQLite 和 MySQL，打算支持哪几种，就分别拿哪几种样本来试。
- 能沿用原格式就继续读写。需要换库时，提供能把旧数据完整导入的办法。多服共用一套库，或服主还要切回旧插件继续写入时，先问清楚哪些服会同时写、旧插件还要能读哪些新数据。
- 搬数据时留意玩家 UUID、世界、坐标、朝向、金额的小数位和时间单位，也要保住表之间的关联。遇到认不出的世界名，保留原值，列出来让服主处理。把它默认为主世界，玩家下次回家就可能出现在同坐标的另一处地方。
- 正式切换前先停写或取一致性快照，拿备份恢复一份测试库，在副本上导入。用事务或临时文件保存结果，把冲突和失败的记录列出来。中途停一次，再用同一份数据重跑，看看会不会多出传送点、重复发物品或多算一笔余额。
- 导完先对记录数，再抽几个玩家对账。余额总数即使分毫不差，也可能打进了别人的账户。最后进服改一条旧记录，重启再查，确认改动确实存下来了。

### 最终验证阶段：

- 从干净环境构建一次，照安装说明把插件放进测试服。空服新装和带旧数据升级各走一遍，看看启动和关服时有没有报错。如果同时发布 Wasm 和 Native，两种都要测。Native 还要在标明支持的平台上试加载。
- 用玩家和控制台执行常用命令，也试试参数填错、权限不足和前置缺失。支持热重载的话，重载后再操作一次，看事件会不会触发两回，刚存的数据还在不在。
- 测传送点插件时，用原玩家账号回到一个带中文名的旧传送点，看落在哪个世界、面朝哪边。改一下位置，重启再传一次，最后让没有权限的玩家试同一条命令。
- 用英文和简体中文客户端触发同一条带参数的提示，看两边各自收到什么。GUI、全息图、声音这些要进游戏看或听。写了支持 Java 版和基岩版，就两端都试。手边没有相应客户端时，留给服主具体的操作和预期结果，标明哪一步还没测。

### 建立文档：

- 在 `README.md` 开头写清适用的 Pumpkin 版本、该下载哪个文件、放在哪个目录、要装哪些前置。给一条装好就能试的命令，写出正常时玩家会看到什么。
- 命令旁边写上别名、权限节点、默认谁能用。配置给一个能照着改的例子，注明改完要重启还是可以重载。与旧版用法有差异、暂时做不了的功能，放在对应条目旁边。
- 给升级旧服的人单独写一段。先列出测过的旧版本和存储格式，再按操作顺序写备份、配置、导入和核对数据的步骤。出错时，服主需要知道去哪里看失败记录、从备份恢复哪些文件或表，以及切换后新增的数据怎么保留。步骤多了，再拆到 `MIGRATION.md`。
- 给下一位维护者留下实际用过的 Pumpkin 提交、SDK、工具链、构建命令和测试环境。测到什么写什么，待测的客户端或数据库版本也点名写清楚。
