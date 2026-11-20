# Repository guidelines

## Scope and structure

This file applies to the whole repository. The repository contains four Dart projects rather than a single workspace:

- `simple_live_core`: shared live-site APIs, models, parsers, and danmaku clients.
- `simple_live_app`: Flutter client for Android, iOS, macOS, Windows, and Linux.
- `simple_live_tv_app`: Flutter client focused on Android TV.
- `simple_live_console`: command-line client built on `simple_live_core`.

The two clients and the console use `simple_live_core` through a relative path dependency. When changing a public core API, parser, model, or protocol implementation, check every consumer that is affected.

## Toolchain

- 技术栈：Dart；Flutter 手机端（Android、iOS、macOS、Windows、Linux）；Flutter TV 端；`simple_live_core` 共享库；基于 core 的 Dart 控制台。Flutter 客户端使用 GetX、Hive 和 `media_kit`。
- Flutter 项目固定使用 FVM Flutter `3.47.1`。手机端 Android 构建使用 Gradle Wrapper（Gradle `8.14`）、Android Gradle Plugin `8.11.1` 和 Kotlin Gradle Plugin `2.2.20`。
- Flutter 项目中的 Dart/Flutter 命令从相应项目目录运行；优先使用 `fvm flutter ...` / `fvm dart ...`。Core 和 console 命令分别从自己的项目目录运行。
- Each project owns its `pubspec.lock`. Keep intentional lockfile changes, but do not regenerate unrelated dependencies.
- Do not commit generated or local state from `.dart_tool/`, `.fvm/`, `build/`, IDE settings, CocoaPods, or platform ephemeral directories.

### 当前 Windows 构建环境

以下是本会话成功构建手机端 ARM64 Release APK 时实际使用的命令和路径。`.task-cache`、Android SDK、JDK 路径属于本机环境；不要把它们当成其他电脑的固定路径，也不要因此自动下载或安装工具。

- Flutter/FVM：项目 `.fvmrc` 固定为 `3.47.1`；本会话从仓库 `.task-cache\fvm` 使用该版本，并将 `.task-cache\pub-cache\bin` 和 `.task-cache\fvm\versions\3.47.1\bin` 临时加入当前 PowerShell 的 `PATH`。
- Android SDK：`D:\application\android-sdk`。
- JDK：`D:\application\jdk-17`（Java 17）。仅在需要构建 Android 时，为当前终端设置 `JAVA_HOME` 并将 JDK 的 `bin` 加入 `PATH`，不修改系统级环境变量。
- Gradle 用户缓存：本会话使用仓库 `.task-cache\gradle`，通过当前终端的 `GRADLE_USER_HOME` 指定。Gradle 本身由项目 Wrapper 管理，不另装 Gradle。

本会话在 `simple_live_app` 目录执行构建前使用以下 PowerShell 环境设置（`$root` 指仓库根目录）：

```powershell
$root = (Get-Location).Path | Split-Path -Parent
$env:PATH = (Join-Path $root .task-cache\pub-cache\bin) + ';' + (Join-Path $root .task-cache\fvm\versions\3.47.1\bin) + ';' + $env:PATH
$env:PUB_CACHE = (Join-Path $root .task-cache\pub-cache)
$env:FVM_CACHE_PATH = (Join-Path $root .task-cache\fvm)
$env:FVM_USE_GIT_CACHE = 'false'
$env:JAVA_HOME = 'D:\application\jdk-17'
$env:ANDROID_HOME = 'D:\application\android-sdk'
$env:GRADLE_USER_HOME = (Join-Path $root .task-cache\gradle)
```

工具用途和常用命令：

- `fvm flutter` / `fvm dart`：使用项目固定版本的 Flutter/Dart；`dart format` 格式化改动文件，`flutter analyze --no-pub` 静态分析，`flutter build apk` 构建 Android 包。
- Flutter/Pub 依赖：本次构建复用了已有依赖并使用 `--no-pub`，没有重新获取依赖。只有 `pubspec.yaml`、SDK 版本或依赖锁定确实改变时，才在对应 Flutter 项目运行 `fvm flutter pub get`。
- 测试：本会话按仓库策略未运行测试。除非用户明确要求，不新增或运行 Flutter/Dart/原生测试。
- Git：修改完成并验证后，只提交本次改动；默认不推送，除非用户明确要求。

手机端 ARM64 Release APK 构建命令（从 `simple_live_app` 目录运行）：

```powershell
fvm flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub
```

成功产物：`build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`。按仓库交付约定，Android 客户端相关改动构建成功后复制到 `D:\本地分享\workspace`，文件名标明版本、`arm64` 和改动内容。不要额外验证 APK 签名、架构、安装或哈希。

## Execution strategy

- 优先复用项目现有工具、已安装依赖、脚本和上述已验证环境，直接实施当前任务。
- 不在每次会话开始时重复枚举全部工具、检查全部环境或搜索替代方案；从当前任务涉及的项目和命令开始。
- 只加载和使用当前任务需要的工具。只有工具不可用、调用失败或相关配置改变时，才针对故障做检查。
- 不擅自安装新工具、升级依赖或切换技术栈；缺少工具时先利用已有固定版本路径和缓存解决。

## Development conventions

- Follow the existing Dart style and the lints in each project's `analysis_options.yaml`.
- Format changed Dart files with `dart format`; avoid repository-wide formatting for a scoped change.
- Keep platform-independent live-site behavior in `simple_live_core`. Keep presentation, routing, persistence, and platform integration in the corresponding Flutter app.
- The Flutter clients use GetX for routing and dependency lookup, Hive for local persistence, and `media_kit` for playback. Extend the existing patterns unless the task explicitly calls for an architectural change.
- Preserve existing public names and stored Hive data compatibility unless a migration is included.
- Never commit credentials, signing files, account cookies, tokens, or private API responses.

## Validation

- 默认只验证代码逻辑：审查调用关系、状态流转、边界条件及受影响的调用方，并按需进行静态分析。
- 除非用户后续明确要求，不自动新增或运行测试，包括 Dart/Flutter 单元测试、Widget/UI 测试、Android 原生单元测试、集成测试、回归测试及真机交互测试；不要运行 `dart test`、`flutter test` 或 Gradle 测试任务，也不要为测试配置额外环境或改用其他测试入口。
- App 的实际使用、交互手感及功能验收由用户完成；交付时如实说明仅完成代码逻辑检查、静态分析或构建，不声称已通过 App 测试。
- `pubspec.yaml` 或 SDK 版本变化时，先获取对应项目的依赖；否则不要为检查而重新获取无关依赖。

按需执行与改动范围匹配的静态分析，不要求逐一运行所有项目：

```sh
cd simple_live_core && dart analyze
cd simple_live_console && dart analyze
cd simple_live_app && fvm flutter analyze --no-pub
cd simple_live_tv_app && fvm flutter analyze --no-pub
```

从直接修改的项目开始检查。修改 `simple_live_core` 时，同时审查受影响的客户端或控制台调用方。原生平台改动通过代码逻辑审查及必要的构建编译检查，不自动运行原生测试。只有本次改动涉及 Android 客户端代码或会影响 Android 客户端的共享代码时，才执行上方 ARM64 正式包构建与复制交付；纯文档、控制台或其他不影响 Android 客户端的改动不构建 APK。

## 用户交流与交付约定

- 用户询问、选项、操作说明、进度更新和结果说明优先使用中文；新增或调整的界面文案使用中文，第三方工具的英文输出以中文概述。
- 仅当本次改动涉及 `simple_live_app` 的 Android 客户端代码，或修改了会影响该 Android 客户端的共享代码时，才为 `simple_live_app` 构建 64 位 Android 正式安装包（ARM64 / `arm64-v8a`）；纯 Web 等不影响 Android 客户端的改动不构建 APK。
- 在 `simple_live_app` 目录按“当前 Windows 构建环境”中的会话级环境设置，使用固定版本执行：`fvm flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub`。依赖发生变化时，先按上面的要求获取依赖并完成代码检查。
- 构建成功后，将 APK 直接复制到 `D:\本地分享\workspace`，文件名应能识别版本、架构和本次修改内容。
- 按用户要求，打包后不额外进行 APK 架构、签名、安装或哈希验证；打包前仅完成代码逻辑检查及必要的静态分析，不自动运行测试，App 测试由用户完成。
