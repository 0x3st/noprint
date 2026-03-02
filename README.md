# anti-det

macOS 优先的极简开源指纹浏览器底座。

当前主路线是你定义的最终形态：

1. 用户下载 `MyBrowser.dmg` 并拖入应用程序
2. 双击 `MyBrowser.app`，菜单栏出现图标
3. 点击“环境 1 / 环境 2”
4. 宿主程序调用 `Contents/Frameworks/Chromium.app`
5. 自动附加 `--user-data-dir` 和 `--antidetect-config` 启动参数

不要求终端用户安装 Python。

## 目录结构

```text
anti-det/
  host/macos/                       # Swift 菜单栏宿主
    Package.swift
    Info.plist
    Sources/MyBrowserHost/
      main.swift
      Resources/
        host.json
        configs/profiles/*.json
  launcher/                         # 研发调试用 CLI（可选）
    antidetect.py
  patches/                          # Chromium patch 栈
    0001-*.patch
    0002-*.patch
    0003-*.patch
  scripts/
    build_chromium.sh               # 拉源码/打补丁/编译 Chromium
    ci_verify_chromium.sh           # GitHub Actions 验证脚本
    build_host_macos.sh             # 编译 Swift 宿主并打包 .app
    package_macos_app.sh            # 组装 MyBrowser.app
    build_macos_dmg.sh              # 生成 MyBrowser.dmg
```

## MyBrowser.app 打包流程（macOS）

1. 编译宿主（Swift）

```bash
make host-swift-build
```

2. 组装 `.app`（需要你提供已编译 Chromium.app 路径）

```bash
make host-build CHROMIUM_APP=/abs/path/to/Chromium.app OUT=dist
```

3. 生成 DMG

```bash
make host-dmg APP=dist/MyBrowser.app DMG=dist/MyBrowser.dmg
```

产物：

- `dist/MyBrowser.app`
- `dist/MyBrowser.dmg`

## 宿主配置（无 Python 依赖）

默认读取顺序：

1. `~/Library/Application Support/MyBrowser/host.json`
2. App 内置 `Contents/Resources/host.json`

宿主会：

1. 读取 profile JSON
2. 生成 `runtime_config.json`
3. 自动扫描共享插件目录（unpacked）
4. 启动 Chromium

关键参数：

- `--user-data-dir=<独立目录>`
- `--antidetect-config=<runtime-config-json>`
- `--disable-extensions-except` / `--load-extension`（如果有共享插件）

## Patch-Driven 工作流

`patches/*.patch` 为唯一魔改来源，不提交 Chromium 巨仓。

当前补丁栈：

1. `0001-add-antidetect-config-switch.patch`
2. `0002-read-antidetect-runtime-json-in-main-delegate.patch`
3. `0003-apply-ua-and-accept-language-from-runtime-config.patch`
4. `0004-plumb-canvas-webgl-seeds-to-child-processes.patch`
5. `0005-apply-seeded-noise-in-canvas2d-and-webgl-readback.patch`
6. `0006-fix-antidetect-switch-visibility-across-platforms.patch`
7. `0007-salt-webgl-vendor-and-renderer-parameters.patch`
8. `0008-add-thread-safe-runtime-config-cache-and-bootstrap-ipc.patch`
9. `0009-hot-reload-runtime-config-on-file-change.patch`

构建入口：

```bash
./scripts/build_chromium.sh
```

常用补丁命令：

```bash
make new-patch N=0004 SLUG=canvas-webgl-seed-in-renderer
make export-patch SRC=.chromium/src COMMIT=HEAD OUT=0004-canvas-webgl-seed-in-renderer.patch
make patch-list
```

## GitHub Actions 远程验证

工作流：`.github/workflows/chromium-patch-verify.yml`

1. PR 默认 `apply-only`（快速验证 patch 可应用）
2. 手动触发可选 `minimal` 或 `full`

推荐参数：

1. `build_mode=minimal`
2. `chromium_ref=origin/main`（或锁定 SHA）
3. `verify_target=chrome/common:common`
4. `ninja_jobs=4~8`

补丁应用策略：

1. 默认 `PATCH_APPLY_STRATEGY=resilient`（`--check` 失败时自动回退 `--3way`）
2. 如需严格模式可设 `PATCH_APPLY_STRATEGY=strict`

## 开发调试 CLI（可选）

`launcher/antidetect.py` 仍可用于本地开发期调试：

```bash
make validate
make dry-run-dev
make launch-dev
```
