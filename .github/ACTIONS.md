# GitHub Actions 构建说明

这些配置用于当前仓库（`sunset-L/dart_simple_live_fork`），不依赖上游仓库的分支、个人 Token 或版本 JSON。
**所有流程只构建 APK 并上传 Actions Artifacts，不创建、更新或发布 GitHub Release。**

## 运行方式

| Actions 中的名称 | 手动运行 | 推送标签触发 | 产物保留 |
| --- | --- | --- | --- |
| 手机端 Android 手动/开发构建 | 支持 | `dev_v*`，例如 `dev_v1.11.49` | 14 天 |
| 手机端 Android 标签构建 | 不支持 | `v*`，例如 `v1.11.49` | 30 天 |
| TV 端 Android 手动/开发构建 | 支持 | `dev_tv_v*`，例如 `dev_tv_v1.6.8` | 14 天 |
| TV 端 Android 标签构建 | 不支持 | `tv_*`，例如 `tv_v1.6.8` | 30 天 |

原来的 `publish_*` 文件名保留，以避免不必要地改变工作流文件路径；其中已没有 Release 发布步骤。
工作流不固定签出 `dev` 或 `master`：手动运行构建选择的分支，标签运行构建该标签的提交。
推送普通分支不会自动构建。

1. 将本次 `.github` 配置提交并推送到 GitHub 的默认分支。手动入口需要默认分支包含对应工作流。
2. 在仓库 **Settings → Actions → General** 确认启用 Actions，并允许配置中使用的 Actions。
3. 配置下文中的 Android 签名 Secrets。
4. 在 **Actions** 选择手机端或 TV 端的“手动/开发构建”，点击 **Run workflow**，选择含有本次配置的分支。
5. 成功后，在这次运行页面底部的 **Artifacts** 下载 APK 压缩包。

也可以给包含新配置的提交推送对应前缀的标签；这仍然只产生 Artifacts，不会发布 Release。
无需配置 `TOKEN` 或个人访问令牌，无需授予 `contents: write` 权限。

## Android 签名 Secrets

新建或 fork 仓库不会复制原仓库的 Secrets。请在当前仓库
**Settings → Secrets and variables → Actions → New repository secret** 中配置：

| 手机端 Secret | TV 端 Secret | 内容 |
| --- | --- | --- |
| `KEYSTORE_BASE64` | `TV_KEYSTORE_BASE64` | 对应签名文件的完整 Base64 文本 |
| `STORE_PASSWORD` | `TV_STORE_PASSWORD` | keystore 密码 |
| `KEY_PASSWORD` | `TV_KEY_PASSWORD` | key 密码 |
| `KEY_ALIAS` | `TV_KEY_ALIAS` | key 别名 |

只运行手机端时，只需手机端四项；只运行 TV 时，只需 TV 四项。
如需两个应用共用自己的签名文件，请将相同内容分别设置到两组 Secrets。
缺少任一项会在配置检查阶段明确失败，不会悄悄改成未签名包或每次生成不同的签名密钥。

**应使用你自己的、妥善备份的签名文件。** 如果 Actions APK 需要覆盖安装已有 APK，必须使用相同签名。
仓库里不要提交签名文件、密码或 Base64 文本；Secrets 的实际值由你在 GitHub 设置中填写。

Windows PowerShell 中可以将本地签名文件转成 Base64 并复制到剪贴板（请替换示例路径）：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\你的私有目录\release-key.jks')) | Set-Clipboard
```

签名文件仅在 runner 临时目录还原，`key.properties` 在构建时生成；两者均不会上传到 Artifacts。
密码通过环境变量传入，并以 Java Properties Unicode 转义保存，不直接拼接到 shell 命令。

## 工具链及产物

- runner：`ubuntu-24.04`，超时 60 分钟。
- Flutter：分别读取应用的 `.fvmrc`，当前均为 `3.47.1`；使用固定的 FVM `4.3.2` 执行 Flutter 命令。
- Java：17；Android API：36；Build Tools：35.0.0；NDK：28.2.13676358。
- 每个 APK 的版本来自对应应用的 `pubspec.yaml`，不会因标签改变而自动升级。
- 每次生成 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三个正式 APK。
- 文件名为 `simple-live-app-<版本及构建号>-<ABI>.apk` 或 `simple-live-tv-<版本及构建号>-<ABI>.apk`。
- CI 获取依赖、检查 Android 工具链并构建；不运行单元、Widget、集成或真机测试。

## 已停用的平台

手机端两个工作流中均保留注释掉的 iOS 构建、IPA 创建和上传步骤，当前不会执行。
由于手机端已移除 `ios`、`macos`、`linux`、`windows` 工程，旧的桌面端构建 job 也已移除，
避免新仓库运行到不存在的工程。这里没有改动任何 App 平台工程或业务代码。
如果以后恢复 iOS，需要恢复工程并配置独立 macOS job 和相应 Xcode，不能直接在 Ubuntu Android job 中取消注释。
