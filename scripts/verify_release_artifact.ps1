param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$InstallerPath,
  [Parameter(Mandatory = $true)][string]$SourceSha,
  [string]$Repo = "luojiang419/huiyun-ai-video-releases",
  [string]$ReleaseNotes = "自动更新能力与发布链路测试。"
)

$ErrorActionPreference = "Stop"
$expectedName = "HuiYunAI-VideoGen-Setup-$Version.exe"
$file = Get-Item -LiteralPath $InstallerPath
if ($file.Name -cne $expectedName) {
  throw "资产名不符合契约：期望 $expectedName，实际 $($file.Name)"
}
if ($file.Length -le 0) { throw "安装包为空" }

$hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
$signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
$buildName = $Version.Substring(1)
$exePath = Join-Path (Split-Path -Parent $PSScriptRoot) `
  "flutter_grsai_video_gen\build\windows\x64\runner\Release\flutter_grsai_image_gen.exe"
$exeVersion = (Get-Item -LiteralPath $exePath).VersionInfo.ProductVersion
if (-not $exeVersion.StartsWith($buildName)) {
  throw "程序产品版本不一致：期望 $buildName，实际 $exeVersion"
}

$artifactDir = $file.Directory.FullName
$manifestPath = Join-Path $artifactDir "update.json"
$checksumPath = Join-Path $artifactDir "$expectedName.sha256"
$notesPath = Join-Path $artifactDir "release-notes.md"
$installerUrl = "https://github.com/$Repo/releases/download/$Version/$expectedName"
$manifest = [ordered]@{
  version = $Version
  installerName = $expectedName
  installerUrl = $installerUrl
  sha256 = $hash
  size = $file.Length
  publishedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  releaseNotes = $ReleaseNotes
  mandatory = $false
  sourceSha = $SourceSha
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
  $manifestPath,
  ($manifest | ConvertTo-Json -Depth 4),
  $utf8NoBom
)
[System.IO.File]::WriteAllText(
  $checksumPath,
  "$hash  $expectedName`n",
  $utf8NoBom
)
[System.IO.File]::WriteAllText(
  $notesPath,
  "$ReleaseNotes`n`nSource commit: $SourceSha`n",
  $utf8NoBom
)

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
  "sha256=$hash" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  "signature=$($signature.Status)" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  "manifest=$manifestPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  "checksum=$checksumPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  "notes=$notesPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}
Write-Host "版本=$Version SHA256=$hash 签名=$($signature.Status)"
