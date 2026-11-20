# Rust Wasm 插件构建与发布模板

这套模板为已有的 Pumpkin Rust 插件添加本地构建、拉取请求检查和 GitHub 发布流程。适用于单个 Cargo 包，也可在 Cargo 工作区中选择一个插件包。插件须能构建为 `wasm32-wasip3` 组件并导出 Pumpkin Wasm API `0.2.0`。每次成功构建生成供服主安装的 `<插件名>.wasm` 和用于核对下载内容的 `SHA256SUMS`。

## 接入已有插件

1. 在**目标插件仓库根目录**执行以下命令，把路径换成本机的 Pumpkin_Agent 目录。如果已有同名工作流或脚本，先核对差异再合并。

   ```sh
   template=/path/to/Pumpkin_Agent/templates/wasm-plugin
   mkdir -p .github
   cp -Ri "$template/.github/." .github/
   ```

2. 在目标仓库的 `.github/plugin.env` 中填写 Cargo 包名和发布文件名。脚本会用 `CARGO_PACKAGE` 匹配 `[package].name`，并查找该包唯一的 `cdylib` 库目标，可以保留已有的 `[lib].name`。插件仓库须提交 `Cargo.lock`，供 `--locked` 构建使用。下面的配置会把 `example-plugin` 发布为 `ExamplePlugin.wasm`。[模板配置文件](.github/plugin.env)

   ```sh
   CARGO_PACKAGE=example-plugin
   PLUGIN_NAME=ExamplePlugin
   ```

   `PLUGIN_NAME` 以字母或数字开头，可包含字母、数字、点、下划线和连字符。商店条目的名称默认与它一致。如果商店名称包含空格或与文件名不同，在同一文件中另加一行 `MARKET_PLUGIN_NAME='Example Plugin'`。

3. 在插件返回给 Pumpkin 的元数据中读取 `PUMPKIN_PLUGIN_VERSION`。下面是 Rust 的 `get_metadata()` 中对应的字段。这样手动输入 `1.2.3` 后，服务端加载日志也会显示 `1.2.3`。本地未设置环境变量时使用 Cargo 包版本。

   ```rust
   version: option_env!("PUMPKIN_PLUGIN_VERSION")
       .unwrap_or(env!("CARGO_PKG_VERSION"))
       .into(),
   ```

## 本地构建

CI 使用 Rust `1.100.0`、WASI SDK `34.0` 和 `wasm-tools 1.263.0`。本地需要 Bash、`jq`、`sha256sum`，并把同版本的 `wasm-tools` 放入 `PATH`。以下命令适用于有 GNU coreutils 的 Linux 环境，从目标插件仓库根目录执行。有 C/C++ 依赖时，将 `/opt/wasi-sdk` 换成 WASI SDK 的实际安装位置。[工作流与工具链下载地址](.github/workflows/build.yml)

```sh
export RUSTUP_TOOLCHAIN=1.100.0
rustup toolchain install "$RUSTUP_TOOLCHAIN" --profile minimal --component rustfmt,clippy --target wasm32-wasip3
export WASI_SDK_PATH=/opt/wasi-sdk
export WASI_SYSROOT="$WASI_SDK_PATH/share/wasi-sysroot"
export CC_wasm32_wasip3="$WASI_SDK_PATH/bin/wasm32-wasip3-clang"
export CXX_wasm32_wasip3="$WASI_SDK_PATH/bin/wasm32-wasip3-clang++"
export AR_wasm32_wasip3="$WASI_SDK_PATH/bin/llvm-ar"
bash .github/scripts/build.sh
(cd target/release-assets && sha256sum -c SHA256SUMS)
```

示例配置下，最后一条命令应输出 `ExamplePlugin.wasm: OK`。构建脚本先运行格式检查和 Clippy，再以 release 配置编译，验证 Wasm 组件及模板要求的导出和 WASI 导入版本，最后替换 `target/release-assets/` 中的附件。使用独立 Cargo 输出目录时，仍在插件仓库根目录的 `target/release-assets/` 取件。[构建脚本](.github/scripts/build.sh)

将其中的 `.wasm` 放入目标测试服的插件目录，核对加载日志中的名称和版本，再执行插件提供的一项操作。所需宿主权限由插件元数据声明，测试服须按实际用途授权。对带独立 Web UI 的项目，另行打包前端资源。模板的正式版与商店流程会核对附件列表，默认只接受组件和校验文件。

## GitHub 发布

| 工作流 | 触发方式 | 结果 |
| --- | --- | --- |
| [Build](.github/workflows/build.yml) | 提交拉取请求 | 只读构建检查，两个文件可从该次运行的 `plugin-wasm` 工件下载，保留 7 天。 |
| [Nightly](.github/workflows/nightly.yml) | 推送到任一分支 | 以本次推送的最后一个提交构建 GitHub 预发布版，标签为 `nightly-YYYY-MM-DD-<提交前12位>`，日期取 UTC。 |
| [Releases](.github/workflows/release.yml) | 在 **Actions → Releases → Run workflow** 选择默认分支并输入版本号 | `1.2.3` 和 `v1.2.3` 都会发布正式版 `v1.2.3`。默认仅发布到 GitHub。 |

### 随构建附上提交更新记录

模板生成的 GitHub 发布说明包含本次构建的提交链接。按迁移指南交付更新记录时，可在目标项目的构建摘要或发布说明中追加本次包含的提交短哈希和标题。多次提交一起推送时，Nightly 可取推送前后两个提交之间的记录，正式版可取上一正式版标签到本次提交之间的记录。下面的命令适用于本地已有这两个版本历史的仓库，把占位值替换为实际提交或标签。

```sh
previous_ref='<上一次推送的提交或上一正式版标签>'
current_ref='<本次构建的提交>'
git log --reverse --format='- %h %s' "${previous_ref}..${current_ref}"
```

首次构建没有上一个版本时，至少记录本次提交的短哈希和标题，可用 `git log -1 --format='- %h %s' HEAD` 取得。复用以上命令到 CI 时，检出范围要覆盖所选的两个版本。[模板的发布说明生成脚本](.github/scripts/publish.sh)

## 可选的 Pumpkin Market 发布

先在商店开发者后台创建条目，再打开插件仓库的 **Settings → Secrets and variables → Actions**。在 **Variables** 中将 `PUMPKIN_MARKET_PLUGIN_ID` 设为管理页面地址中的数字 ID，在 **Secrets** 中将 `Pumpkin_Market_Token` 设为商店令牌。令牌需要 `plugins:read`、`plugins:update`、`plugins:versions:upload` 和 `plugins:publish` 权限。读取隐藏草稿的开发者看板还需要 `analytics:read`。[Pumpkin Market 开发者后台](https://market.pumpkinmc.org/dashboard/plugins)

发布者在 **Releases** 勾选商店选项后，工作流从对应的 GitHub 正式版下载原附件，核对 SHA-256，上传到指定条目的 `stable` 渠道，并读回版本和审核状态。草稿或被退回的条目会在资料齐备后提交审核，审核中的条目沿用原审核。GitHub 正式版已发布时，也可以用相同版本号补传商店。审核步骤提示资料缺失时，在商店补全后使用 **Re-run failed jobs** 继续。

## 常见问题

| 现象 | 核对方法 |
| --- | --- |
| 报错 `Expected one cdylib target` | 在仓库根目录运行 `cargo metadata --locked --no-deps --format-version 1`。核对包名和库目标，并确认所选包在 `[lib]` 中声明了 `crate-type = ["cdylib"]`。 |
| Clippy 在 `wit_bindgen::generate!` 处报 `too_many_arguments` | 查看诊断是否指向 WIT 自动生成的函数。若参数个数由接口固定，可仅在生成绑定的模块上标注 `#[allow(clippy::too_many_arguments)]`，保留业务代码的完整检查。 |
| 报告缺少 v0.2.0 导出，或要求 WASI 0.3 | 对本次 Cargo 编译出的组件执行 `wasm-tools component wit <组件路径>`，核对 WIT 版本、同步入口、异步回调和 WASI 导入，修正绑定或编译目标后重新构建。 |
| 本地构建通过，测试服加载失败 | 查看服务端的第一条加载错误，核对服务端版本、已启用的 Wasm API 及插件请求的权限，并确认安装的是本次产物。 |

## 模板验证记录

2026-11-20，在独立 Cargo workspace 中将包 `example-plugin` 的库目标 `independent_guest_lib` 构建为 `ExamplePlugin.wasm`。输出目录只有组件和 `SHA256SUMS`，执行 `sha256sum -c SHA256SUMS` 返回 `ExamplePlugin.wasm: OK`。用启用了 `plugin-v0_2` 的 Pumpkin（提交 `e318ec5f`）加载后，日志显示 `Loaded ExamplePlugin (1.2.3-nightly.20261120+abcdef123456)`，随后正常卸载并停服。工作流通过 actionlint。GitHub 发布、商店上传和重试路径使用模拟接口验证。

模板改编自 PumpGsit 的构建与发布脚本，保留其 GPL-3.0-only 许可证。[来源提交](https://github.com/Q2297045667/PumpGsit/tree/e061ad93b8638b000ebea8f434a4786621dbcc41/.github) · [模板许可证](.github/LICENSE-Pumpkin-build)
