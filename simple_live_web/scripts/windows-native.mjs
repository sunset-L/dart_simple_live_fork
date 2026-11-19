import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

function sourceDigest(packageRoot) {
  const files = [
    "hook/build.dart",
    "lib/src/quickjs_bindings.g.dart",
    ...readdirSync(join(packageRoot, "third_party/quickjs-ng"))
      .filter((file) => /\.(c|h)$/.test(file))
      .map((file) => `third_party/quickjs-ng/${file}`),
  ].sort();
  const digest = createHash("sha256");
  for (const file of files) {
    digest
      .update(`${file}\n`)
      .update(readFileSync(join(packageRoot, file), "utf8").replace(/\r\n/g, "\n"))
      .update("\n");
  }
  return digest.digest("hex");
}

export function prepareWindowsServer(
  root,
  dart,
  {
    kernelPath,
    nativeLibraryPath,
    relativeNativeLibrary = false,
  } = {},
) {
  if (process.arch !== "x64") {
    throw new Error(
      "预编译 QuickJS 目前只支持 Windows x64，请使用 64 位 Node.js 和 Dart SDK。",
    );
  }
  const nativeDir = join(root, "native/windows-x64");
  const metadata = JSON.parse(
    readFileSync(join(nativeDir, "manifest.json"), "utf8"),
  );
  const library = join(nativeDir, "dart_quickjs.dll");
  if (!existsSync(library)) {
    throw new Error(
      "缺少随项目提供的 native/windows-x64/dart_quickjs.dll，请恢复此文件，无需安装编译工具。",
    );
  }
  const libraryDigest = createHash("sha256")
    .update(readFileSync(library))
    .digest("hex");
  if (libraryDigest !== metadata.sha256) {
    throw new Error("QuickJS DLL 已损坏或被替换，请恢复与 manifest.json 配套的文件。");
  }
  const packagesFile = join(root, ".dart_tool/package_config.json");
  const packages = JSON.parse(readFileSync(packagesFile, "utf8"));
  const quickjs = packages.packages.find(
    (entry) => entry.name === metadata.package,
  );
  if (!quickjs) {
    throw new Error("缺少 dart_quickjs 依赖，请先执行 dart pub get。");
  }
  const packageRoot = fileURLToPath(
    new URL(quickjs.rootUri, pathToFileURL(packagesFile)),
  );
  if (sourceDigest(packageRoot) !== metadata.sourceSha256) {
    throw new Error(
      "dart_quickjs 源码与预编译 DLL 不匹配，请恢复已提交的 pubspec.lock，或更新配套 DLL；不会自动调用 C++ 编译工具。",
    );
  }

  const sdkBin = dirname(dart);
  const runtime = join(sdkBin, "dartaotruntime.exe");
  const compiler = join(sdkBin, "snapshots/gen_kernel_aot.dart.snapshot");
  const platform = resolve(sdkBin, "../lib/_internal/vm_platform_strong.dill");
  if (![runtime, compiler, platform].every(existsSync)) {
    throw new Error("Dart SDK 不完整，请将 DART_EXECUTABLE 指向完整 SDK 的 dart.exe。");
  }
  const cache = join(root, ".dart_tool/simple_live_web");
  mkdirSync(cache, { recursive: true });
  const assetsFile = join(cache, "native_assets.json");
  const kernel = kernelPath ?? join(cache, "server.dill");
  const assetFile = nativeLibraryPath ?? library;
  const assetPath = relativeNativeLibrary
    ? relative(dirname(kernel), assetFile).split(sep).join("\\")
    : assetFile;
  if (relativeNativeLibrary && /^[A-Za-z]:\\/.test(assetPath)) {
    throw new Error("便携 kernel 与 QuickJS DLL 必须位于同一磁盘，才能使用相对资源路径");
  }
  writeFileSync(
    assetsFile,
    JSON.stringify({
      "format-version": [1, 0, 0],
      "native-assets": {
        [metadata.architecture]: {
          [metadata.assetId]: [
            relativeNativeLibrary ? "relative" : "absolute",
            assetPath,
          ],
        },
      },
    }),
  );
  console.log(
    "使用项目内预编译 QuickJS；只编译 Dart 后端，不调用 Visual Studio 或 Windows SDK。",
  );
  // Invoke Dart's kernel compiler directly so native build hooks never run.
  const result = spawnSync(
    runtime,
    [
      compiler,
      `--platform=${platform}`,
      `--packages=${packagesFile}`,
      `--native-assets=${assetsFile}`,
      `--output=${kernel}`,
      join(root, "bin/server.dart"),
    ],
    { cwd: root, stdio: "inherit", windowsHide: true },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error("Dart 后端编译失败，未启动旧的缓存程序。");
  }
  return kernel;
}
