# Rust Wasm 插件构建与发布模板

把这套 GitHub Actions 复制到已有的 Pumpkin Rust 插件仓库，即可构建 `wasm32-wasip3` 组件，生成 `<插件名>.wasm` 和 `SHA256SUMS` 两个发布附件。模板面向 Pumpkin Wasm API `0.2.0`，适用于单个 Cargo 包，也能在 workspace 中选定一个插件包。

## 接入已有插件

1. 在**目标插件仓库根目录**执行以下命令，把路径换成本机的 Pumpkin_Agent 目录。如果已有同名工作流或脚本，先核对差异再合并。

   ```sh
   template=/path/to/Pumpkin_Agent/templates/wasm-plugin
   mkdir -p .github
   cp -Ri "$template/.github/." .github/
   ```

2. 编辑 [`.github/plugin.env`](.github/plugin.env)。例如 Cargo 包名为 `example-plugin`，希望玩家下载 `ExamplePlugin.wasm`，填写以下两项。构建脚本会从 Cargo 元数据查找该包的 `cdylib`，可以保留已有的 `[lib].name`。插件仓库须提交 `Cargo.lock`，供 `--locked` 构建使用。

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

CI 使用 Rust `1.100.0`、WASI SDK `34.0` 和 `wasm-tools 1.263.0`。本地需要 Bash、`jq`、`sha256sum`，并把同版本的 `wasm-tools` 放入 `PATH`。下面以 Linux 为例，从目标仓库根目录执行。如果依赖包含 C/C++ 代码，请将 `/opt/wasi-sdk` 换成实际安装位置。[工作流与工具链下载地址](.github/workflows/build.yml)

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

脚本依次检查 Rust 格式、Clippy、release 编译结果和组件接口，再打包校验通过的 Wasm。插件需要的宿主权限由插件元数据声明，服务端加载时按实际用途授权。

## GitHub 发布

| 工作流 | 触发方式 | 结果 |
| --- | --- | --- |
| [Build](.github/workflows/build.yml) | 提交拉取请求 | 只读构建检查，两个文件可从该次运行的 `plugin-wasm` 工件下载。 |
| [Nightly](.github/workflows/nightly.yml) | 推送到任一分支 | 以本次推送的最后一个提交构建 GitHub 预发布版，标签为 `nightly-YYYY-MM-DD-<提交前12位>`，日期取 UTC。 |
| [Releases](.github/workflows/release.yml) | 在 **Actions → Releases → Run workflow** 选择默认分支并输入版本号 | `1.2.3` 和 `v1.2.3` 都会发布正式版 `v1.2.3`。默认仅发布到 GitHub。 |

**可选的 Pumpkin Market 发布**需要先在商店开发者后台创建条目，然后打开插件仓库的 **Settings → Secrets and variables → Actions**。在 **Variables** 中将 `PUMPKIN_MARKET_PLUGIN_ID` 设为管理页面地址中的数字 ID，在 **Secrets** 中将 `Pumpkin_Market_Token` 设为商店令牌。令牌需要 `plugins:read`、`plugins:update`、`plugins:versions:upload` 和 `plugins:publish` 权限。读取隐藏草稿的开发者看板还需要 `analytics:read`。[Pumpkin Market 开发者后台](https://market.pumpkinmc.org/dashboard/plugins)

发布者在 **Releases** 勾选商店选项后，工作流从对应的 GitHub 正式版下载原附件，核对 SHA-256，上传到指定条目的 `stable` 渠道，并读回版本和审核状态。草稿或被退回的条目会检查资料并提交审核；仍在审核中的条目沿用原审核。GitHub 正式版已发布时，也可以用相同版本号补传商店。审核步骤提示资料缺失时，在商店补全后使用 **Re-run failed jobs** 继续。

## 模板验证记录

2026-11-20，在独立 Cargo workspace 中将包 `example-plugin` 的库目标 `independent_guest_lib` 构建为 `ExamplePlugin.wasm`。输出目录只有组件和 `SHA256SUMS`，执行 `sha256sum -c SHA256SUMS` 返回 `ExamplePlugin.wasm: OK`。用启用了 `plugin-v0_2` 的 Pumpkin（提交 `e318ec5f`）加载后，日志显示 `Loaded ExamplePlugin (1.2.3-nightly.20261120+abcdef123456)`，随后正常卸载并停服。工作流通过 actionlint；GitHub 发布、商店上传和重试路径使用模拟接口验证。

模板改编自 PumpGsit 的构建与发布脚本，保留其 GPL-3.0-only 许可证。[来源提交](https://github.com/Q2297045667/PumpGsit/tree/e061ad93b8638b000ebea8f434a4786621dbcc41/.github) · [模板许可证](.github/LICENSE-Pumpkin-build)
