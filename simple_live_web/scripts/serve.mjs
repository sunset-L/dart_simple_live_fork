import { existsSync, realpathSync } from "node:fs";
import { spawn } from "node:child_process";
import { delimiter, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { prepareWindowsServer } from "./windows-native.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const executable = process.platform === "win32" ? "dart.exe" : "dart";
const bundled = resolve(
  root,
  "../.task-cache/fvm/versions/3.47.1/bin/cache/dart-sdk/bin",
  executable,
);
const requestedDart =
  process.env.DART_EXECUTABLE || (existsSync(bundled) ? bundled : "dart");
const locatedDart = [
  requestedDart,
  ...(process.env.PATH ?? "")
    .split(delimiter)
    .map((directory) =>
      resolve(directory, requestedDart === "dart" ? executable : requestedDart),
    ),
].find(existsSync);
const dart = locatedDart ? realpathSync(locatedDart) : requestedDart;
if (!existsSync(resolve(root, ".dart_tool/package_config.json"))) {
  console.error(
    "Run dart pub get in simple_live_web before starting the server.",
  );
  process.exit(1);
}
const lite = process.argv.includes("--lite");
try {
  const args = lite
    ? [
        "--packages=.dart_tool/package_config.json",
        "-DSIMPLE_LIVE_NO_NATIVE=true",
        "bin/server.dart",
      ]
    : process.platform === "win32"
      ? [prepareWindowsServer(root, dart)]
      : ["run", "bin/server.dart"];
  const directVm = resolve(dirname(dart), "dartvm.exe");
  const command =
    !lite && process.platform === "win32" && existsSync(directVm)
      ? directVm
      : dart;
  const child = spawn(command, args, {
    cwd: root,
    stdio: "inherit",
    windowsHide: true,
  });
  child.on("error", (error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
  child.on("exit", (code) => {
    process.exitCode = code ?? 1;
  });
  for (const signal of ["SIGINT", "SIGTERM"])
    process.on(signal, () => child.kill());
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
