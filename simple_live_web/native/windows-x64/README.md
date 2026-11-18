# Windows x64 QuickJS

此目录是随项目分发的第三方运行依赖，不是临时编译缓存。请将 DLL、清单和许可证一起保留。

- 来源：`https://github.com/xiaoyaocz/dart_quickjs`
- 版本：`1.0.0`
- 源码提交：`a31682801e209f925cdb90fcf4e379e512b713d2`
- 文件：`dart_quickjs.dll`，约 1.2 MB，Windows x64。
- 构建方式：原依赖的 `hook/build.dart`，使用本机已有 MSVC 构建。
- 许可证：QuickJS-ng 的 MIT 许可证，见 `LICENSE`。
- DLL 导入依赖：只有 Windows 自带的 `KERNEL32.dll`，无需额外 VC++ 运行库。

`manifest.json` 记录 DLL 的 SHA-256 和对应源码指纹。启动时校验 DLL，并检查依赖中的构建脚本、Dart FFI 绑定、QuickJS-ng 顶层 C 源码和头文件；换行符统一为 LF，避免不同电脑的 Git 换行设置造成误判。依赖内容不匹配时停止启动，不会自动编译、下载或安装工具。

在 `simple_live_web` 目录执行 `npm run server` 或 `npm run server:native`。Windows 启动器用 Dart SDK 自带的 kernel 编译器编译后端，显式登记此 DLL，然后运行生成的 kernel，不执行 `dart run` 的原生构建钩子。缓存可重新生成，项目路径可以变化，后端源码修改后重启即可生效。

更新 `dart_quickjs` 时应同步提供匹配的新 DLL 和清单；只更新 Dart 依赖不够。未来如需重新编译或安装系统工具，应先说明用途、来源及替代方案，取得用户同意。不要自动安装生成工具或 Windows SDK。

此方案仅用于 Windows x64 网页后端，不改变 core 或 Flutter 客户端的原生编译方式。Windows ARM64、macOS 和 Linux 不能直接使用这个 DLL。
