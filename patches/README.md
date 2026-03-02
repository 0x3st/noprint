# Patch-Driven 约定

这个目录只存你对 Chromium 的最小化补丁文件，不存 Chromium 源码本体。

## 规则

1. 一个能力一个补丁（例如 `0001-add-antidetect-switch.patch`）。
2. 补丁尽量小，优先改 Blink / Network 入口层，不做无关重构。
3. 补丁基线建议绑定到固定 Chromium commit，便于升级时重放和冲突定位。
4. `scripts/build_chromium.sh` 会自动按文件名排序应用 `patches/*.patch`。

## 推荐切分

- `0001` 启动参数：`--antidetect-config` 注册和解析
- `0002` 网络层：UA / Client Hints / Accept-Language 注入
- `0003` 渲染层：Canvas / WebGL 盐值逻辑
- `0004` 指纹配置 IPC / 线程安全缓存

## 当前补丁

- `0001-add-antidetect-config-switch.patch`：注册 `--antidetect-config` 开关。

## 工具

- `scripts/new_patch.sh`：创建补丁模板。
- `scripts/export_patch.sh`：把 Chromium 源码中的 commit 导出到 `patches/`。
- `scripts/ci_verify_chromium.sh`：CI 中执行 patch apply / minimal build / full build 验证。
