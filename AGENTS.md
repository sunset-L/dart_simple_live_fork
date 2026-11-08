# Repository guidelines

## Scope and structure

This file applies to the whole repository. The repository contains four Dart projects rather than a single workspace:

- `simple_live_core`: shared live-site APIs, models, parsers, and danmaku clients.
- `simple_live_app`: Flutter client for Android, iOS, macOS, Windows, and Linux.
- `simple_live_tv_app`: Flutter client focused on Android TV.
- `simple_live_console`: command-line client built on `simple_live_core`.

The two clients and the console use `simple_live_core` through a relative path dependency. When changing a public core API, parser, model, or protocol implementation, check every consumer that is affected.

## Toolchain

- Flutter is pinned to `3.47.1` with FVM in both Flutter projects.
- Run Flutter commands from the relevant app directory with `fvm flutter ...`; use `fvm dart ...` when a Flutter project's Dart SDK is required.
- Run `fvm install` in each Flutter project if the pinned SDK is not available locally.
- Run Dart commands for `simple_live_core` and `simple_live_console` from their own directories.
- Each project owns its `pubspec.lock`. Keep intentional lockfile changes, but do not regenerate unrelated dependencies.
- Do not commit generated or local state from `.dart_tool/`, `.fvm/`, `build/`, IDE settings, CocoaPods, or platform ephemeral directories.

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

按需执行对应项目的静态分析，不要求逐一运行所有项目：

```sh
cd simple_live_core && dart analyze
cd simple_live_console && dart analyze
cd simple_live_app && fvm flutter analyze --no-pub
cd simple_live_tv_app && fvm flutter analyze --no-pub
```

从直接修改的项目开始检查。修改 `simple_live_core` 时，同时审查受影响的客户端或控制台调用方。原生平台改动通过代码逻辑审查及必要的构建编译检查，不自动运行原生测试。下方约定的 ARM64 正式包构建与复制交付仍照常执行。

## 用户交流与交付约定

- 用户询问、选项、操作说明、进度更新和结果说明优先使用中文；新增或调整的界面文案使用中文，第三方工具的英文输出以中文概述。
- 本仓库代码修改完成后，默认自动为 `simple_live_app` 构建 64 位 Android 正式安装包（ARM64 / `arm64-v8a`）。
- 在 `simple_live_app` 目录使用固定版本的 FVM 执行：`fvm flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub`。依赖发生变化时，先按上面的要求获取依赖并完成代码检查。
- 构建成功后，将 APK 直接复制到 `D:\本地分享\workspace`，文件名应能识别版本、架构和本次修改内容。
- 按用户要求，打包后不额外进行 APK 架构、签名、安装或哈希验证；打包前仅完成代码逻辑检查及必要的静态分析，不自动运行测试，App 测试由用户完成。
