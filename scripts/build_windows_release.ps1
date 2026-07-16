param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$ProjectDir = "flutter_grsai_video_gen",
  [string]$ArtifactDir = "release-artifacts",
  [string]$IsccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = "Stop"
if ($Version -notmatch '^V\d+\.\d+\.\d+$') {
  throw "版本必须是 VMAJOR.MINOR.PATCH：$Version"
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = Resolve-Path (Join-Path $root $ProjectDir)
$artifacts = Join-Path $root $ArtifactDir
$buildName = $Version.Substring(1)
$releaseDir = Join-Path $project "build\windows\x64\runner\Release"
$assetName = "HuiYunAI-VideoGen-Setup-$Version.exe"

if (-not (Test-Path -LiteralPath $IsccPath)) {
  throw "未找到 Inno Setup 编译器：$IsccPath"
}

Push-Location $project
try {
  & flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失败" }
  & flutter build windows --release --no-pub `
    "--build-name=$buildName" `
    "--build-number=1" `
    "--dart-define=APP_RELEASE_VERSION=$Version"
  if ($LASTEXITCODE -ne 0) { throw "Flutter Windows Release 构建失败" }
} finally {
  Pop-Location
}

$releaseData = Join-Path $releaseDir "data"
New-Item -ItemType Directory -Force -Path $releaseData | Out-Null
Copy-Item -LiteralPath (Join-Path $project "data\Defaults") -Destination $releaseData -Recurse -Force
Copy-Item -LiteralPath (Join-Path $project "data\Settings") -Destination $releaseData -Recurse -Force

$settingsDir = Join-Path $releaseData "Settings"
Copy-Item `
  -LiteralPath (Join-Path $project "data\Defaults\config.template.json") `
  -Destination (Join-Path $settingsDir "config.json") `
  -Force
Copy-Item `
  -LiteralPath (Join-Path $project "data\Defaults\config.template.json") `
  -Destination (Join-Path $releaseData "Defaults\config.json") `
  -Force
Copy-Item `
  -LiteralPath (Join-Path $root "AI规则\system_prompt.txt") `
  -Destination (Join-Path $settingsDir "system_prompt.txt") `
  -Force

if (Test-Path -LiteralPath $artifacts) {
  Remove-Item -LiteralPath $artifacts -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

& $IsccPath `
  "/DMyAppVersion=$Version" `
  "/DMyAppOutputBaseFilename=HuiYunAI-VideoGen-Setup-$Version" `
  "/DMyAppOutputDir=$artifacts" `
  (Join-Path $project "windows\installer.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup 安装包构建失败" }

$installer = Join-Path $artifacts $assetName
if (-not (Test-Path -LiteralPath $installer)) {
  throw "安装包未按契约生成：$installer"
}
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
  "installer=$installer" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}
Write-Host "安装包已生成：$installer"
