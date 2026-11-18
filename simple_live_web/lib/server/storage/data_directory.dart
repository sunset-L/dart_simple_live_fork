import 'dart:io';

Directory localDataDirectory() {
  final env = Platform.environment;
  final override = env['SIMPLE_LIVE_DATA_DIR'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final base = Platform.isWindows
      ? env['APPDATA']
      : env['XDG_DATA_HOME'] ??
            (env['HOME'] == null ? null : '${env['HOME']}/.local/share');
  if (base == null || base.isEmpty) {
    throw const FileSystemException('无法定位本地数据目录');
  }
  return Directory('$base${Platform.pathSeparator}simple-live-web');
}
