param(
  [Parameter(Mandatory = $true)]
  [string] $StartBat
)

$ErrorActionPreference = 'Stop'
$startPath = [IO.Path]::GetFullPath($StartBat)
$bundleRoot = Split-Path -Parent $startPath
$shortcutPath = Join-Path $bundleRoot 'Simple Live Web.lnk'
$iconPath = Join-Path $bundleRoot 'simple-live-web.ico'

if (-not (Test-Path -LiteralPath $startPath -PathType Leaf)) {
  throw ('启动文件不存在：' + $startPath)
}
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
  throw ('应用图标不存在：' + $iconPath)
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $null
try {
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $iconLocation = $iconPath + ',0'
  if ($shortcut.TargetPath -ne $startPath -or
      $shortcut.WorkingDirectory -ne $bundleRoot -or
      $shortcut.IconLocation -ne $iconLocation) {
    $shortcut.TargetPath = $startPath
    $shortcut.Arguments = ''
    $shortcut.WorkingDirectory = $bundleRoot
    $shortcut.IconLocation = $iconLocation
    $shortcut.Description = '启动 Simple Live Web'
    $shortcut.Save()
  }
} finally {
  if ($shortcut) { [Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null }
  [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
}
