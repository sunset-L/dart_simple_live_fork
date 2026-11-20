import { createHash } from "node:crypto";
import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { delimiter, dirname, join, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { prepareWindowsServer } from "./windows-native.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repository = resolve(root, "..");
const packageInfo = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: "inherit",
    windowsHide: true,
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} 退出码：${result.status}`);
  return result.stdout?.trim();
}

function filesIn(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? filesIn(path) : [path];
  });
}

function findDart() {
  const candidates = [
    process.env.DART_EXECUTABLE,
    join(repository, ".task-cache/fvm/versions/3.47.1/bin/cache/dart-sdk/bin/dart.exe"),
    join(root, ".runtime/dart-sdk/bin/dart.exe"),
    ...(process.env.PATH ?? "").split(delimiter).map((path) => join(path, "dart.exe")),
  ];
  const dart = candidates.find((path) => path && existsSync(path));
  if (!dart) throw new Error("未找到现有 Dart SDK，请设置 DART_EXECUTABLE；不会下载安装工具");
  return realpathSync(dart);
}

function collectLicenses(destination, sdkRoot) {
  mkdirSync(destination, { recursive: true });
  copyFileSync(join(sdkRoot, "LICENSE"), join(destination, "Dart-SDK-LICENSE"));
  copyFileSync(join(root, "native/windows-x64/LICENSE"), join(destination, "QuickJS-LICENSE"));
  const copied = new Set();
  function collect(directory, name) {
    if (!existsSync(directory)) return;
    for (const file of readdirSync(directory, { withFileTypes: true })) {
      if (!file.isFile() || !/^(license|licence|copying|notice)(\.|$)/i.test(file.name)) continue;
      const target = `${name.replaceAll("/", "__")}-${file.name}`;
      if (copied.has(target)) continue;
      copied.add(target);
      copyFileSync(join(directory, file.name), join(destination, target));
    }
  }
  const packagesFile = join(root, ".dart_tool/package_config.json");
  const packages = JSON.parse(readFileSync(packagesFile, "utf8"));
  const base = pathToFileURL(packagesFile);
  for (const entry of packages.packages) {
    collect(fileURLToPath(new URL(entry.rootUri, base)), `dart-${entry.name}`);
  }
  const nodeModules = join(root, "node_modules");
  for (const entry of readdirSync(nodeModules, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
    if (entry.name.startsWith("@")) {
      for (const child of readdirSync(join(nodeModules, entry.name), { withFileTypes: true })) {
        if (child.isDirectory()) collect(join(nodeModules, entry.name, child.name), `${entry.name}/${child.name}`);
      }
    } else collect(join(nodeModules, entry.name), entry.name);
  }
}

try {
  if (process.platform !== "win32" || process.arch !== "x64") {
    throw new Error("此打包命令仅支持 Windows x64，使用现有工具且不安装任何软件");
  }
  const dart = findDart();
  const sdkBin = dirname(dart);
  const runtime = join(sdkBin, "dartvm.exe");
  if (!existsSync(runtime)) throw new Error("Dart SDK 缺少 dartvm.exe，无法创建便携包");
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const name = `simple-live-web-${packageInfo.version}-windows-x64-${stamp}`;
  const release = join(root, "release");
  const bundle = join(release, name);
  mkdirSync(bundle, { recursive: true });
  for (const directory of ["runtime", "server", "native", "scripts"]) {
    mkdirSync(join(bundle, directory), { recursive: true });
  }
  console.log("正在构建正式网页静态资源...");
  run(process.execPath, [join(root, "node_modules/typescript/bin/tsc"), "-b"]);
  run(process.execPath, [join(root, "node_modules/vite/bin/vite.js"), "build"]);
  cpSync(join(root, "dist"), join(bundle, "dist"), { recursive: true });
  copyFileSync(runtime, join(bundle, "runtime/dartvm.exe"));
  copyFileSync(join(root, "native/windows-x64/dart_quickjs.dll"), join(bundle, "native/dart_quickjs.dll"));
  const powershell = join(process.env.SystemRoot ?? "C:\\Windows", "System32/WindowsPowerShell/v1.0/powershell.exe");
  run(powershell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
    "-File", join(root, "scripts/create-windows-icon.ps1"),
    "-SourcePng", join(root, "public/assets/logo.png"), "-DestinationIco", join(bundle, "simple-live-web.ico"),
  ]);
  prepareWindowsServer(root, dart, {
    kernelPath: join(bundle, "server/server.dill"),
    nativeLibraryPath: join(bundle, "native/dart_quickjs.dll"),
    relativeNativeLibrary: true,
  });
  const bom = "\uFEFF";
  writeFileSync(join(bundle, "scripts/start-windows.ps1"),
    bom + readFileSync(join(root, "scripts/start-windows.ps1"), "utf8").replace(/^\uFEFF/, ""));
  writeFileSync(join(bundle, "scripts/create-shortcut.ps1"),
    bom + readFileSync(join(root, "scripts/create-shortcut.ps1"), "utf8").replace(/^\uFEFF/, ""));
  writeFileSync(join(bundle, "start.bat"),
    readFileSync(join(root, "scripts/portable-start.bat"), "utf8").replace(/\r?\n/g, "\r\n"));
  copyFileSync(join(root, "scripts/portable-README.md"), join(bundle, "README.md"));
  collectLicenses(join(bundle, "licenses"), resolve(sdkBin, ".."));
  const gitResult = spawnSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", windowsHide: true });
  if (gitResult.status !== 0) throw new Error("无法读取 Git 源提交，已停止生成交付 ZIP");
  const dartVersion = run(dart, ["--version"], { stdio: "pipe", encoding: "utf8" });
  const manifest = {
    format: 1,
    version: packageInfo.version,
    sourceCommit: gitResult.stdout.trim(),
    architecture: "windows_x64",
    dartVersion,
    builtAt: new Date().toISOString(),
    files: filesIn(bundle).map((path) => ({
      path: relative(bundle, path).replaceAll("\\", "/"),
      size: statSync(path).size,
      sha256: createHash("sha256").update(readFileSync(path)).digest("hex"),
    })),
  };
  writeFileSync(join(bundle, "portable.json"), JSON.stringify(manifest, null, 2) + "\n");
  const zip = join(release, `${name}.zip`);
  console.log("正在压缩便携 ZIP...");
  run(powershell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command",
    "Add-Type -AssemblyName System.IO.Compression.FileSystem; " +
    "[IO.Compression.ZipFile]::CreateFromDirectory($env:SIMPLE_LIVE_PACKAGE_DIRECTORY, $env:SIMPLE_LIVE_PACKAGE_ZIP, [IO.Compression.CompressionLevel]::Optimal, $true)",
  ], { env: { ...process.env, SIMPLE_LIVE_PACKAGE_DIRECTORY: bundle, SIMPLE_LIVE_PACKAGE_ZIP: zip } });
  const rawBytes = filesIn(bundle).reduce((sum, path) => sum + statSync(path).size, 0);
  console.log(`便携目录：${bundle}`);
  console.log(`ZIP：${zip}`);
  console.log(`解压后 ${(rawBytes / 1024 / 1024).toFixed(1)} MiB；ZIP ${(statSync(zip).size / 1024 / 1024).toFixed(1)} MiB`);
  console.log("解压后双击 start.bat；无需安装工具，关闭命令窗口即停止服务。");
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
