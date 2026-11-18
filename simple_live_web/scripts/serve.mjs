import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const executable = process.platform === "win32" ? "dart.exe" : "dart";
const bundled = resolve(
  root,
  "../.task-cache/fvm/versions/3.47.1/bin/cache/dart-sdk/bin",
  executable,
);
const dart =
  process.env.DART_EXECUTABLE || (existsSync(bundled) ? bundled : "dart");
if (!existsSync(resolve(root, ".dart_tool/package_config.json"))) {
  console.error(
    "Run dart pub get in simple_live_web before starting the server.",
  );
  process.exit(1);
}
const lite = process.argv.includes("--lite");
// Full mode builds QuickJS for Douyu signing; lite mode is explicitly opt-in.
const child = spawn(
  dart,
  lite
    ? [
        "--packages=.dart_tool/package_config.json",
        "-DSIMPLE_LIVE_NO_NATIVE=true",
        "bin/server.dart",
      ]
    : ["run", "bin/server.dart"],
  { cwd: root, stdio: "inherit", windowsHide: true },
);
child.on("error", (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
child.on("exit", (code) => {
  process.exitCode = code ?? 1;
});
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => child.kill());
