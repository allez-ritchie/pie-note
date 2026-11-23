# 一键构建 Windows 桌面端（检查依赖 → 构建 → 打印产物路径）。
#
# 用法（PowerShell）：
#   pwsh -File scripts/build_windows.ps1                 # release 构建（默认）
#   pwsh -File scripts/build_windows.ps1 -DebugBuild     # debug 构建
#   pwsh -File scripts/build_windows.ps1 -Bundle         # 额外打成 dist/pie-note-windows-x64-<mode>.zip
#
# 注意：参数名不能用 -Debug —— 那是 PowerShell 的通用参数，会冲突。
#
# Windows 端不需要 libsecret 那类额外开发包：密码走 flutter_secure_storage 的
# Windows 实现（系统凭据管理器），链接期只需 MSVC 与 Windows SDK。
# 前置条件见 AGENTS.md 4.3：Flutter 在 PATH 上，且安装了 Visual Studio 的
# 「使用 C++ 的桌面开发」工作负载（含 MSVC 与 Windows 10/11 SDK）。
[CmdletBinding()]
param(
  [switch]$DebugBuild,
  [switch]$Bundle
)

$ErrorActionPreference = 'Stop'
$mode = if ($DebugBuild) { 'debug' } else { 'release' }

$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

# 国内镜像：首次 pub get / 拉引擎产物时需要。
$env:FLUTTER_STORAGE_BASE_URL = if ($env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL } else { 'https://storage.flutter-io.cn' }
$env:PUB_HOSTED_URL = if ($env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL } else { 'https://pub.flutter-io.cn' }

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw '[build-windows] 未找到 flutter，请先把 Flutter SDK 的 bin 目录加入 PATH。'
}

Write-Host "[build-windows] flutter build windows --$mode"
flutter build windows "--$mode"
if ($LASTEXITCODE -ne 0) {
  throw "[build-windows] flutter build windows --$mode 失败（退出码 $LASTEXITCODE）。"
}

$bundleDir = Join-Path $rootDir "build\windows\x64\runner\$(if ($mode -eq 'debug') { 'Debug' } else { 'Release' })"
Write-Host "[build-windows] 产物：$bundleDir"

if ($Bundle) {
  $distDir = Join-Path $rootDir 'dist'
  New-Item -ItemType Directory -Force -Path $distDir | Out-Null
  $archive = Join-Path $distDir "pie-note-windows-x64-$mode.zip"
  if (Test-Path $archive) { Remove-Item $archive -Force }
  Compress-Archive -Path (Join-Path $bundleDir '*') -DestinationPath $archive
  Write-Host "[build-windows] 归档：$archive"
}
