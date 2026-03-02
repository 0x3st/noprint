# shared_extensions

把需要全局共享的 unpacked 插件放在这个目录下，每个插件一个子目录：

```
shared_extensions/
  ublock-origin/
    manifest.json
  immersive-translate/
    manifest.json
```

启动器会自动扫描含 `manifest.json` 的子目录，并通过：

- `--disable-extensions-except=...`
- `--load-extension=...`

在所有 profile 中共享加载同一套插件。

