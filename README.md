# anti-det

极简开源指纹浏览器底座（macOS 优先）最小骨架。

当前仓库目标不是直接分发浏览器，而是提供：

- 本地 JSON 配置驱动的多环境启动器
- 100% 物理隔离的 profile（独立 `user_data_dir`）
- 全局共享插件目录（避免每个环境重复安装插件）
- Patch-Driven Chromium 构建工作流骨架

## 目录结构

```
anti-det/
  launcher/
    antidetect.py             # 启动器（读取 JSON -> 组装 Chromium 启动参数）
  configs/
    global.example.json       # 全局配置模板
    profiles/
      dev.example.json        # profile 模板
  shared_extensions/          # 全局共享插件目录（unpacked）
  patches/                    # 你的 Chromium patch 文件（*.patch）
  scripts/
    bootstrap_local.sh        # 初始化本地配置
    build_chromium.sh         # 拉源码/打补丁/编译
  Makefile
```

## 快速开始（macOS）

1. 初始化本地配置

```bash
make bootstrap
```

2. 修改 `configs/global.json` 中的 `chromium_path`（默认是 Chrome 稳定版路径）

3. 校验配置

```bash
make validate
```

4. 先 dry-run 看命令行参数

```bash
make dry-run-dev
```

5. 真正启动

```bash
make launch-dev
```

## 启动器支持

```bash
python3 launcher/antidetect.py --global-config configs/global.json validate --profile dev
python3 launcher/antidetect.py --global-config configs/global.json list-extensions
python3 launcher/antidetect.py --global-config configs/global.json launch --profile dev --dry-run
```

## JSON 设计（最小）

`configs/global.json`:

```json
{
  "chromium_path": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "base_data_dir": "data",
  "shared_extensions_dir": "shared_extensions",
  "chromium_args": ["--no-first-run", "--no-default-browser-check"]
}
```

`configs/profiles/dev.json`:

```json
{
  "id": "dev",
  "proxy": {"server": "http://127.0.0.1:7890"},
  "fingerprint": {
    "user_agent": "...",
    "canvas_seed": "dev-seed-001",
    "webgl_seed": "dev-seed-001"
  },
  "chromium_args": ["--window-size=1280,900"]
}
```

启动器会自动追加：

- `--user-data-dir=<独立目录>`
- `--antidetect-config=<runtime-config-json-绝对路径>`
- 共享插件参数（若 `shared_extensions_dir` 下有 unpacked 插件）

并在每个 profile 的目录下生成标准化运行时配置文件：

- `data/<profile-id>/antidetect/runtime_config.json`

## Patch-Driven 工作流

Chromium 魔改能力落在 `patches/*.patch`。构建脚本会执行：

1. 拉取/同步官方 Chromium 源码到 `.chromium/src`
2. 按文件名顺序应用 `patches/*.patch`
3. 执行 `gn gen` + `ninja` 编译

```bash
./scripts/build_chromium.sh
```

当前已内置第一个基线补丁：

- `patches/0001-add-antidetect-config-switch.patch`

环境变量：

- `CHROMIUM_REF`：指定编译基线（默认 `origin/main`）
- `CHROMIUM_WORK_DIR`：Chromium 工作目录（默认 `.chromium`）
- `CHROMIUM_OUT_DIR`：输出目录（默认 `out/Default`）

补丁日常命令：

```bash
# 新建补丁模板
make new-patch N=0002 SLUG=load-antidetect-config-at-startup

# 从 Chromium 源码导出某个 commit 为 patch 文件
make export-patch SRC=.chromium/src COMMIT=HEAD OUT=0002-load-antidetect-config-at-startup.patch

# 查看 patch 栈
make patch-list
```

## GitHub Actions 远程验证

已内置工作流：

- `.github/workflows/chromium-patch-verify.yml`

行为：

- `pull_request`：默认跑 `apply-only`（只验证 patch 能否应用到指定 Chromium 基线）
- `workflow_dispatch`：可手动选
  - `apply-only`
  - `minimal`（推荐，编译最小目标 `chrome/common:common`）
  - `full`（全量 `chrome`，耗时和磁盘都很高）

手动触发建议：

1. `build_mode=minimal`
2. `chromium_ref=origin/main`（或你锁定的 commit）
3. `verify_target=chrome/common:common`
4. `ninja_jobs=4~8`（降低 OOM 风险）

工作流会先自动清理 runner 磁盘，再拉 Chromium、应用 `patches/*.patch`，最后按模式执行验证。

对应脚本：

- `scripts/ci_verify_chromium.sh`

## 说明

- 当前仓库不包含 Chromium C++ 具体 hook 实现；这是下一阶段在 `patches/` 里逐步沉淀的内容。
- 启动器已经预留 `--antidetect-config` 参数传递链路，便于你在 Chromium 侧解析并应用指纹参数。
