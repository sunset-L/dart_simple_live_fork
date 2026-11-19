[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Worker,
    [switch]$Portable,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtime = Join-Path $root '.runtime'

function Quote-Argument([string]$Value) {
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
}

function Initialize-ProcessGroup {
    if ('SimpleLiveProcessGroup' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public sealed class SimpleLiveProcessGroup : IDisposable {
    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimits {
        public long PerProcessTime, PerJobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcesses;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IoCounters {
        public ulong ReadOperations, WriteOperations, OtherOperations;
        public ulong ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ExtendedLimits {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo {
        public int Size;
        public string Reserved, Desktop, Title;
        public uint X, Y, Width, Height, XChars, YChars, Fill, Flags;
        public ushort ShowWindow, ReservedBytes;
        public IntPtr ReservedPointer, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo {
        public IntPtr Process, Thread;
        public uint ProcessId, ThreadId;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass,
        ref ExtendedLimits info, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcess(string application, StringBuilder command,
        IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles,
        uint flags, IntPtr environment, string directory,
        ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")]
    static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);
    IntPtr job;

    public SimpleLiveProcessGroup() {
        job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) throw new Win32Exception();
        var limits = new ExtendedLimits();
        limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if (!SetInformationJobObject(job, 9, ref limits,
                (uint)Marshal.SizeOf(typeof(ExtendedLimits)))) {
            int error = Marshal.GetLastWin32Error();
            Dispose();
            throw new Win32Exception(error);
        }
    }
    public Process Start(string executable, string arguments, string directory) {
        var startup = new StartupInfo();
        startup.Size = Marshal.SizeOf(typeof(StartupInfo));
        ProcessInfo info;
        var command = new StringBuilder("\"" + executable + "\" " + arguments);
        if (!CreateProcess(executable, command, IntPtr.Zero, IntPtr.Zero, false,
                4, IntPtr.Zero, directory, ref startup, out info))
            throw new Win32Exception();
        try {
            if (!AssignProcessToJobObject(job, info.Process))
                throw new Win32Exception();
            var process = Process.GetProcessById((int)info.ProcessId);
            var processHandle = process.Handle;
            if (ResumeThread(info.Thread) == uint.MaxValue)
                throw new Win32Exception();
            return process;
        } catch {
            TerminateProcess(info.Process, 1);
            throw;
        } finally {
            CloseHandle(info.Thread);
            CloseHandle(info.Process);
        }
    }
    public void Dispose() {
        if (job != IntPtr.Zero) {
            CloseHandle(job);
            job = IntPtr.Zero;
        }
    }
}
'@
}

# Assign suspended children before resuming them. An outer job owns the worker;
# a nested job can clean up a failed startup without closing the setup prompt.
if (-not $Worker) {
    $group = $null
    try {
        Initialize-ProcessGroup
        $group = New-Object SimpleLiveProcessGroup
        $powershell = Join-Path $PSHOME 'powershell.exe'
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
            (Quote-Argument $PSCommandPath) + ' -Worker'
        if ($CheckOnly) { $arguments += ' -CheckOnly' }
        if ($Portable) { $arguments += ' -Portable' }
        if ($NoBrowser) { $arguments += ' -NoBrowser' }
        $process = $group.Start($powershell, $arguments, $root)
        $process.WaitForExit()
        $code = $process.ExitCode
    } catch {
        Write-Host "无法启动受控进程：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host '请使用 Windows 10/11 自带的 Windows PowerShell 5.1，并检查系统执行策略。'
        $code = 1
    } finally {
        if ($group) { $group.Dispose() }
    }
    exit $code
}

function Show-ManualSetup {
    Write-Host ''
    Write-Host '可手动安装或解压下面的工具，然后重新双击 start.bat：' -ForegroundColor Yellow
    Write-Host '  Node.js 22.12+ / 24 LTS（64 位，自带 npm）：https://nodejs.org/en/download'
    Write-Host '  完整 Dart SDK 3.13+（推荐 3.13.1）：https://dart.dev/get-dart/archive'
    Write-Host '  Git for Windows / MinGit：https://git-scm.com/download/win'
    Write-Host '安装后打开新窗口，使 PATH 生效；独立 Dart 可设置 DART_EXECUTABLE 指向 dart.exe。'
    Write-Host '项目目录不可写时，将完整仓库移动到个人可写目录，再启动；无需管理员权限。'
    Write-Host '网络下载失败时可用浏览器下载，按 README 的 .runtime 目录结构解压。'
    Write-Host '不需要 Flutter、Visual Studio、Windows SDK、VC++ 运行库或浏览器插件。'
}

function Assert-RuntimePath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($runtime).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw '本地工具操作路径超出 .runtime，已停止操作'
    }
    $absolute
}

function Probe([string]$Executable, [string[]]$Arguments) {
    if (-not $Executable -or -not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        return $null
    }
    try {
        $text = (& $Executable @Arguments 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0) { return $text }
    } catch { }
    return $null
}

function Find-Tools {
    $node = $null
    $dart = $null
    $git = $null
    $nodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue
    foreach ($path in @((Join-Path $runtime 'node\node.exe'), $nodeCommand.Source)) {
        $version = Probe $path @('--version')
        if ($version -match '^v(\d+)\.(\d+)\.') {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            if (($major -gt 22 -or ($major -eq 22 -and $minor -ge 12)) -and
                (Probe $path @('-p', 'process.arch')) -eq 'x64' -and
                (Test-Path -LiteralPath (Join-Path (Split-Path $path) 'node_modules\npm\bin\npm-cli.js'))) {
                $node = @{ path = [IO.Path]::GetFullPath($path); version = $version }
                break
            }
        }
    }
    $dartCommand = Get-Command dart.exe -CommandType Application -ErrorAction SilentlyContinue
    foreach ($path in @(
        $env:DART_EXECUTABLE,
        (Join-Path $runtime 'dart-sdk\bin\dart.exe'),
        (Join-Path $root '..\.task-cache\fvm\versions\3.47.1\bin\cache\dart-sdk\bin\dart.exe'),
        $dartCommand.Source
    )) {
        $version = Probe $path @('--version')
        if ($version -notmatch 'Dart SDK version: (3\.(\d+)\.\d+).*windows_x64') { continue }
        if ([int]$Matches[2] -lt 13) { continue }
        $number = $Matches[1]
        $bin = Split-Path $path
        $required = @(
            'dartaotruntime.exe', 'snapshots\gen_kernel_aot.dart.snapshot',
            '..\lib\_internal\vm_platform_strong.dill'
        )
        if (@($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $bin $_)) }).Count) {
            continue
        }
        $dart = @{ path = [IO.Path]::GetFullPath($path); version = $number }
        break
    }
    $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue
    foreach ($path in @((Join-Path $runtime 'git\cmd\git.exe'), $gitCommand.Source)) {
        $version = Probe $path @('--version')
        if ($version -match '^git version 2\.') {
            $git = @{ path = [IO.Path]::GetFullPath($path); version = $version }
            break
        }
    }
    @{ node = $node; dart = $dart; git = $git }
}

function Has-PackageConfig {
    $file = Join-Path $root '.dart_tool\package_config.json'
    try {
        $config = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        $base = [Uri]::new([IO.Path]::GetFullPath($file))
        foreach ($package in $config.packages) {
            $uri = [Uri]::new($base, [string]$package.rootUri)
            if (-not $uri.IsFile -or -not (Test-Path -LiteralPath $uri.LocalPath -PathType Container)) {
                return $false
            }
        }
        return $config.configVersion -eq 2 -and $config.packages.Count -gt 0
    } catch { return $false }
}

function Download-Tool([string]$Url, [string]$Destination, [string]$Hash) {
    $destination = Assert-RuntimePath $Destination
    if ((Test-Path -LiteralPath $destination) -and
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $Hash) {
        Write-Host "复用已校验的下载：$(Split-Path $destination -Leaf)"
        return
    }
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $request = [Net.HttpWebRequest]::Create($Url)
        $request.UserAgent = 'SimpleLive-Web-Setup'
        $request.Timeout = 120000
        $request.ReadWriteTimeout = 60000
        $response = $request.GetResponse()
        if ($response.ResponseUri.Scheme -ne 'https') { throw '不允许非 HTTPS 下载' }
        $inputStream = $response.GetResponseStream()
        $outputStream = [IO.File]::Create($destination)
        $buffer = New-Object byte[] 131072
        $received = 0L
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $last = 0L
        while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $received += $count
            if ($received -gt 1GB) { throw '下载文件超过 1 GB，已停止' }
            $outputStream.Write($buffer, 0, $count)
            if ($clock.ElapsedMilliseconds - $last -lt 250) { continue }
            $last = $clock.ElapsedMilliseconds
            $percent = -1
            if ($response.ContentLength -gt 0) {
                $percent = [Math]::Min(100, [int](100 * $received / $response.ContentLength))
            }
            Write-Progress -Activity "下载 $(Split-Path $destination -Leaf)" `
                -Status ("已下载 {0:N1} MB" -f ($received / 1MB)) -PercentComplete $percent
        }
    } finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($response) { $response.Dispose() }
        Write-Progress -Activity "下载 $(Split-Path $destination -Leaf)" -Completed
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $Hash) {
        Remove-Item -LiteralPath $destination -Force
        throw '下载文件 SHA-256 不匹配，未解压或执行，请重试或手动安装'
    }
    Write-Host '下载完成，SHA-256 校验通过。'
}

function Install-Tool([string]$Name, [hashtable]$Package) {
    $downloads = Join-Path $runtime 'downloads'
    New-Item -ItemType Directory -Path $downloads -Force | Out-Null
    $zip = Join-Path $downloads "$Name-$($Package.version).zip"
    Write-Host "下载 $Name $($Package.version)：$($Package.url)"
    Download-Tool $Package.url $zip $Package.hash
    $stage = Assert-RuntimePath (Join-Path $runtime ([Guid]::NewGuid().ToString('N')))
    $target = Assert-RuntimePath (Join-Path $runtime $Package.target)
    try {
        New-Item -ItemType Directory -Path $stage | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                $entryPath = [IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
                if (-not $entryPath.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    throw '压缩包路径不合法，已停止解压'
                }
            }
        } finally { $archive.Dispose() }
        Write-Host "正在解压 $Name 到 .runtime\$($Package.target) ..."
        Expand-Archive -LiteralPath $zip -DestinationPath $stage
        $source = $stage
        if ($Package.folder) { $source = Assert-RuntimePath (Join-Path $stage $Package.folder) }
        if (-not (Test-Path -LiteralPath (Join-Path $source $Package.executable))) {
            throw '压缩包未包含所需可执行文件，未完成安装'
        }
        if (Test-Path -LiteralPath $target) {
            $backup = Assert-RuntimePath (Join-Path $runtime ("previous-$Name-" + [Guid]::NewGuid().ToString('N')))
            Move-Item -LiteralPath (Assert-RuntimePath $target) -Destination $backup
            Write-Host "旧工具目录已保留到 $backup"
        }
        Move-Item -LiteralPath (Assert-RuntimePath $source) -Destination $target
        Write-Host "$Name 安装完成。"
    } finally {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath (Assert-RuntimePath $stage) -Recurse -Force
        }
    }
}

function Run-Command([string]$Executable, [string[]]$Arguments, [string]$Label) {
    Write-Host ''
    Write-Host $Label -ForegroundColor Cyan
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label 失败（退出码 $LASTEXITCODE）。请检查上方命令输出和网络/目录权限。"
    }
}

function Select-Port([string]$Configured, [int]$Default, [int[]]$Excluded) {
    $preferred = $Default
    if ($Configured -and
        (-not [int]::TryParse($Configured, [ref]$preferred) -or $preferred -lt 1024 -or $preferred -gt 65535)) {
        throw '端口必须是 1024 至 65535 之间的整数'
    }
    for ($port = $preferred; $port -le [Math]::Min(65535, $preferred + 100); $port++) {
        if ($Excluded -contains $port) { continue }
        $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $port)
        try {
            $listener.Start()
            if ($port -ne $preferred) { Write-Host "端口 $preferred 已占用，改用 $port。" }
            return $port
        } catch [Net.Sockets.SocketException] {
        } finally { $listener.Stop() }
    }
    throw '未找到空闲端口，请设置 SIMPLE_LIVE_WEB_PORT 和 PORT 后重试'
}

function Wait-Ready([Diagnostics.Process]$Process, [string]$Url, [bool]$Api) {
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Process.HasExited) { throw "服务启动失败（退出码 $($Process.ExitCode)），请查看上方输出" }
        try {
            if ($Api) {
                $result = Invoke-RestMethod $Url -Headers @{'X-Simple-Live' = 'web'} -TimeoutSec 2
                if ($result.status -eq $true -and $result.native -eq $true) { return }
            } else {
                $result = Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 2
                if ($result.StatusCode -eq 200) { return }
            }
        } catch { }
        Start-Sleep -Milliseconds 300
    }
    throw '服务启动超时，请检查上方输出；可重新启动或手动指定空闲端口'
}

function Start-Services([hashtable]$Tools, [int]$WebPort, [int]$ApiPort) {
    if (-not $Tools.node -or -not $Tools.dart) {
        throw '未找到可用的 Node.js 或完整 Dart SDK，无法直接启动'
    }
    Initialize-ProcessGroup
    $services = New-Object SimpleLiveProcessGroup
    $api = $null
    $web = $null
    try {
        $env:DART_EXECUTABLE = $Tools.dart.path
        $paths = @((Split-Path $Tools.node.path), (Split-Path $Tools.dart.path))
        if ($Tools.git) { $paths += Split-Path $Tools.git.path }
        $env:PATH = ($paths -join ';') + ';' + $env:PATH
        $env:PORT = "$ApiPort"
        $env:SIMPLE_LIVE_SERVE_STATIC = '0'
        Write-Host ''
        Write-Host '正在启动 Dart API（使用预编译 QuickJS，不进行前端 build）...' -ForegroundColor Cyan
        $api = $services.Start(
            $Tools.node.path, (Quote-Argument (Join-Path $root 'scripts\serve.mjs')), $root
        )
        Wait-Ready $api "http://127.0.0.1:$ApiPort/api/health" $true
        Write-Host '正在启动 Vite 开发服务...' -ForegroundColor Cyan
        $arguments = (Quote-Argument (Join-Path $root 'node_modules\vite\bin\vite.js')) +
            " --host 127.0.0.1 --port $WebPort --strictPort"
        $web = $services.Start($Tools.node.path, $arguments, $root)
        Wait-Ready $web "http://127.0.0.1:$WebPort/" $false
        return @{ group = $services; api = $api; web = $web }
    } catch {
        $services.Dispose()
        foreach ($process in @($api, $web)) {
            if ($process) {
                $process.WaitForExit(5000) | Out-Null
                $process.Dispose()
            }
        }
        throw
    }
}

function Start-Portable {
    $services = $null
    $api = $null
    try {
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or
            $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or -not [Environment]::Is64BitOperatingSystem) {
            throw '便携版仅支持 Windows 10/11 x64，不支持 Windows ARM64 或 32 位系统'
        }
        Set-Location -LiteralPath $root
        $manifestPath = Join-Path $root 'portable.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw '缺少 portable.json，请完整解压便携 ZIP 后重新启动'
        }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($manifest.format -ne 1 -or $manifest.architecture -ne 'windows_x64') {
            throw '便携包清单格式或架构不受支持，请下载 Windows x64 完整包'
        }
        foreach ($file in @('runtime/dartvm.exe', 'server/server.dill', 'native/dart_quickjs.dll', 'dist/index.html')) {
            $entry = $manifest.files | Where-Object { $_.path -eq $file } | Select-Object -First 1
            $path = Join-Path $root $file
            if (-not $entry -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) {
                throw "文件缺失或校验失败：$file。请重新解压完整便携包。"
            }
        }
        Write-Host "Simple Live Web $($manifest.version) - Windows x64 便携版" -ForegroundColor Cyan
        Write-Host '运行所需资源已随包提供，无需安装或下载开发工具。'
        if ($CheckOnly) {
            Write-Host '便携版文件检查通过；未启动服务。' -ForegroundColor Green
            return
        }
        $configuredPort = $env:SIMPLE_LIVE_WEB_PORT
        if (-not $configuredPort) { $configuredPort = $env:PORT }
        $port = Select-Port $configuredPort 23236 @()
        $env:PORT = "$port"
        $env:SIMPLE_LIVE_SERVE_STATIC = '1'
        Initialize-ProcessGroup
        $services = New-Object SimpleLiveProcessGroup
        $api = $services.Start(
            (Join-Path $root 'runtime\dartvm.exe'),
            (Quote-Argument (Join-Path $root 'server\server.dill')), $root
        )
        $url = "http://127.0.0.1:$port"
        Wait-Ready $api "$url/api/health" $true
        Wait-Ready $api "$url/" $false
        Write-Host ''
        Write-Host "网页访问地址：$url" -ForegroundColor Green
        Write-Host "本机数据目录：$(if ($env:SIMPLE_LIVE_DATA_DIR) { $env:SIMPLE_LIVE_DATA_DIR } else { Join-Path $env:APPDATA 'simple-live-web' })"
        Write-Host '关闭此命令窗口或按 Ctrl+C 即停止本次服务；关闭浏览器不会退出服务。'
        if (-not $NoBrowser) {
            try {
                # Explorer opens the browser outside the service job so cleanup only stops our server.
                $shell = New-Object -ComObject Shell.Application
                try { $shell.ShellExecute($url) }
                finally { [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null }
            } catch {
                Write-Host '无法自动打开默认浏览器，请手动访问上面的网页地址。' -ForegroundColor Yellow
            }
        }
        while (-not $api.HasExited) { Start-Sleep -Seconds 1 }
        throw "服务已退出（退出码 $($api.ExitCode)），请查看上方错误信息"
    } finally {
        if ($services) { $services.Dispose() }
        if ($api) { $api.Dispose() }
    }
}

if ($Portable) {
    try {
        Start-Portable
        exit 0
    } catch {
        Write-Host "便携版启动失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host '请完整解压 ZIP，不要直接在压缩包内运行。不会自动下载或安装工具。'
        exit 1
    }
}

$running = $null
try {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or
        $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or -not [Environment]::Is64BitOperatingSystem) {
        throw '此启动器及预编译 QuickJS 仅支持 Windows x64，不支持 Windows ARM64 或 32 位系统'
    }
    Set-Location -LiteralPath $root
    if (-not (Test-Path -LiteralPath (Join-Path $root '..\simple_live_core\packages\tars_dart\pubspec.yaml'))) {
        throw '缺少 simple_live_core，请获取完整仓库，不能只复制 simple_live_web 文件夹'
    }
    $manifest = Get-Content -LiteralPath 'native\windows-x64\manifest.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath 'native\windows-x64\dart_quickjs.dll' -Algorithm SHA256).Hash -ne $manifest.sha256) {
        throw '项目内 QuickJS DLL 校验失败，请恢复 native/windows-x64 及对应锁文件，无需安装 C++ 工具'
    }
    $packages = @{
        node = @{
            version = '24.22.3'; target = 'node'; folder = 'node-v24.22.3-win-x64'; executable = 'node.exe'
            url = 'https://nodejs.org/dist/v24.22.3/node-v24.22.3-win-x64.zip'
            hash = 'e612af99f626ab415ea225af6bce5c971feb448cb5cae250bb1c3fa50c5f7d9f'
        }
        dart = @{
            version = '3.13.1'; target = 'dart-sdk'; folder = 'dart-sdk'; executable = 'bin\dart.exe'
            url = 'https://storage.googleapis.com/dart-archive/channels/stable/release/3.13.1/sdk/dartsdk-windows-x64-release.zip'
            hash = 'f3fd0fa8f3bc7982bbf08eb1bca84148fb4ee0767e75faa07ec9c11c40ab2ff7'
        }
        git = @{
            version = '2.56.1'; target = 'git'; folder = ''; executable = 'cmd\git.exe'
            url = 'https://github.com/git-for-windows/git/releases/download/v2.56.1.windows.1/MinGit-2.56.1-64-bit.zip'
            hash = '4a92850b6e917da4fd010669b614b55dccf5b0ec333a534cc4be4700dfefdafd'
        }
    }
    $tools = Find-Tools
    Write-Host 'Simple Live Web - Windows 开发模式' -ForegroundColor Cyan
    foreach ($name in @('node', 'dart', 'git')) {
        if ($tools[$name]) { Write-Host "$name : $($tools[$name].version)  $($tools[$name].path)" }
        else { Write-Host "$name : 缺少或版本/架构不符合要求" -ForegroundColor Yellow }
    }
    if ($CheckOnly) {
        Write-Host "npm 启动入口存在：$(Test-Path -LiteralPath 'node_modules\vite\bin\vite.js')；Dart 包路径有效：$(Has-PackageConfig)"
        Write-Host '正常启动时优先直接运行现有环境，只有启动失败才提示准备工具或依赖。'
        Write-Host '仅检查环境，未下载、安装、获取依赖或启动服务。'
        exit 0
    }
    $webPort = Select-Port $env:SIMPLE_LIVE_WEB_PORT 23236 @()
    $apiPort = Select-Port $env:PORT 23238 @($webPort)
    [Console]::WriteLine('使用现有环境直接启动，不下载或安装工具。')
    try {
        $running = Start-Services $tools $webPort $apiPort
    } catch {
        Write-Host ''
        Write-Host "直接启动失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host '本次尝试启动的服务已关闭，请先查看上方错误。'
    }
    if (-not $running) {
        $missing = @('node', 'dart', 'git' | Where-Object { -not $tools[$_] })
        Write-Host ''
        Write-Host '可按锁文件准备项目依赖后重试，以下操作需要确认：' -ForegroundColor Yellow
        foreach ($name in $missing) {
            Write-Host "  $name $($packages[$name].version) 便携版 -> .runtime\$($packages[$name].target)"
            Write-Host "  来源：$($packages[$name].url)"
        }
        if ($missing.Count) {
            Write-Host '用途：Node/npm 运行前端；Dart 运行 API；Git 获取锁定的 Git 依赖。'
            Write-Host '缺少的工具仅解压到项目 .runtime；不改系统 PATH、注册表或安装全局软件。'
        } else {
            Write-Host '工具已齐全，不会下载安装 Node.js、Dart 或 Git，仅重新准备项目依赖。'
        }
        Write-Host '  npm ci --progress=true --no-audit --no-fund：按 package-lock 重新安装项目依赖。'
        Write-Host '  dart pub get --enforce-lockfile：按 pubspec.lock 获取 Dart 包，不更新锁文件。'
        Write-Host 'QuickJS DLL 已自带；无需浏览器插件、Flutter、Visual Studio 或 Windows SDK。'
        Write-Host '依赖准备不一定能解决权限、端口或配置问题；也可按错误提示手动处理后重新打开。'
        $prompt = '按 Enter 同意重新准备项目依赖并重试，输入其他内容取消'
        if ($missing.Count) { $prompt = '按 Enter 同意下载缺少的工具、准备项目依赖并重试，输入其他内容取消' }
        $answer = Read-Host $prompt
        if ($answer -ne '') { Write-Host '已取消，未下载工具或更改项目依赖。'; exit 0 }
        foreach ($file in @('package-lock.json', 'pubspec.lock')) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "缺少 $file，请恢复已提交的锁文件后重试"
            }
        }
        New-Item -ItemType Directory -Path $runtime -Force | Out-Null
        $probeFile = Assert-RuntimePath (Join-Path $runtime ([Guid]::NewGuid().ToString('N') + '.tmp'))
        [IO.File]::WriteAllText($probeFile, 'write-check')
        Remove-Item -LiteralPath $probeFile
        foreach ($name in $missing) { Install-Tool $name $packages[$name] }
        $tools = Find-Tools
        if (-not $tools.node -or -not $tools.dart -or -not $tools.git) {
            throw '工具安装后仍不满足要求，请按手动安装说明处理'
        }
        $env:DART_EXECUTABLE = $tools.dart.path
        $env:PATH = (Split-Path $tools.node.path) + ';' + (Split-Path $tools.dart.path) +
            ';' + (Split-Path $tools.git.path) + ';' + $env:PATH
        if (-not $env:PUB_CACHE) { $env:PUB_CACHE = Join-Path $runtime 'pub-cache' }
        $npmCli = Join-Path (Split-Path $tools.node.path) 'node_modules\npm\bin\npm-cli.js'
        Run-Command $tools.node.path @($npmCli, 'ci', '--progress=true', '--no-audit', '--no-fund') '安装 npm 项目依赖'
        Run-Command $tools.dart.path @('pub', 'get', '--enforce-lockfile') '获取锁定的 Dart 依赖'
        Write-Host '准备完成，正在重新启动；若仍失败则显示原因，不重复要求下载安装。'
        $running = Start-Services $tools $webPort $apiPort
    }
    Write-Host ''
    Write-Host "网页访问地址：http://127.0.0.1:$webPort" -ForegroundColor Green
    Write-Host "API 地址：http://127.0.0.1:$apiPort （不是网页入口）"
    Write-Host "本机数据目录：$(if ($env:SIMPLE_LIVE_DATA_DIR) { $env:SIMPLE_LIVE_DATA_DIR } else { Join-Path $env:APPDATA 'simple-live-web' })"
    Write-Host '关闭此窗口或按 Ctrl+C，会关闭本次启动的所有服务；不会关闭其他窗口的服务。'
    Write-Host '前端支持热更新；修改 Dart 后端后请关闭窗口，再双击 start.bat。'
    while ($true) {
        if ($running.api.HasExited -or $running.web.HasExited) { throw '一个服务已退出，正在关闭本次启动的所有服务' }
        Start-Sleep -Seconds 1
    }
} catch {
    Write-Host ''
    Write-Host "启动失败：$($_.Exception.Message)" -ForegroundColor Red
    Show-ManualSetup
    exit 1
} finally {
    if ($running) {
        $running.group.Dispose()
        $running.api.Dispose()
        $running.web.Dispose()
    }
}
