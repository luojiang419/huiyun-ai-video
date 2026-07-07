param(
  [string]$Version = "",
  [string]$Repo = "luojiang419/huiyun-ai-video-releases",
  [string]$ReleaseNotes = "",
  [bool]$Mandatory = $false
)

$ErrorActionPreference = "Stop"

function Test-CommandExists {
  param([string]$Name)
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function ConvertTo-AssetUrlName {
  param([string]$Name)
  return [System.Uri]::EscapeDataString($Name)
}

function Assert-LastExitCode {
  param([string]$Message)
  if ($LASTEXITCODE -ne 0) {
    throw $Message
  }
}

function Get-GitHubToken {
  $token = (& gh auth token).Trim()
  Assert-LastExitCode "无法读取 GitHub CLI token"
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "GitHub CLI token 为空"
  }
  return $token
}

function Get-AppReleaseVersion {
  param([string]$ProjectRoot)

  $versionFile = Join-Path $ProjectRoot "lib\\constants\\app_version.dart"
  if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "未找到版本文件：$versionFile"
  }

  $content = Get-Content -LiteralPath $versionFile -Raw
  $match = [regex]::Match(
    $content,
    "appReleaseVersion\s*=\s*'(?<version>[^']+)'"
  )
  if (-not $match.Success) {
    throw "无法从版本文件中解析 appReleaseVersion"
  }

  return $match.Groups['version'].Value.Trim()
}

function Remove-ReleaseAssetIfExists {
  param(
    [object]$Release,
    [string[]]$Names
  )

  foreach ($asset in $Release.assets) {
    if (($Names -contains $asset.name) -or $asset.name.EndsWith("$Version.exe")) {
      gh api -X DELETE "repos/$Repo/releases/assets/$($asset.id)" --silent
      Assert-LastExitCode "删除旧 Release 资产失败：$($asset.name)"
    }
  }
}

function Upload-ReleaseAsset {
  param(
    [int64]$ReleaseId,
    [string]$FilePath,
    [string]$AssetName,
    [string]$ContentType,
    [string]$Token
  )

  $encodedName = ConvertTo-AssetUrlName $AssetName
  $uploadUrl = "https://uploads.github.com/repos/$Repo/releases/$ReleaseId/assets?name=$encodedName"
  return Invoke-RestMethod `
    -Uri $uploadUrl `
    -Method Post `
    -Headers @{
      Authorization = "Bearer $Token"
      Accept = "application/vnd.github+json"
      "X-GitHub-Api-Version" = "2022-11-28"
    } `
    -InFile $FilePath `
    -ContentType $ContentType
}

function Write-Utf8NoBomFile {
  param(
    [string]$Path,
    [string]$Content
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if (-not (Test-CommandExists "gh")) {
  throw "未找到 GitHub CLI：gh"
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Resolve-Path (Join-Path $projectRoot "..")

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = Get-AppReleaseVersion -ProjectRoot $projectRoot
}
if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
  $ReleaseNotes = "影视版 $Version 更新发布。"
}

$versionDir = Join-Path $workspaceRoot "dist\影视版\影视版-$Version"
$localInstallerName = "影视版-安装包-$Version.exe"
$installerName = "HuiYunAI-VideoGen-Setup-$Version.exe"
$installerPath = Join-Path $versionDir $localInstallerName

if (-not (Test-Path -LiteralPath $installerPath)) {
  throw "安装包不存在：$installerPath"
}

$fileInfo = Get-Item -LiteralPath $installerPath
$hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
$publishedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$updateJsonPath = Join-Path $versionDir "update.json"
$notesPath = Join-Path $versionDir "release-notes.md"
Set-Content -LiteralPath $notesPath -Value $ReleaseNotes -Encoding UTF8

gh repo view $Repo 1>$null
Assert-LastExitCode "无法访问 GitHub 仓库：$Repo"

$releaseTags = gh release list --repo $Repo --limit 100 --json tagName | ConvertFrom-Json
Assert-LastExitCode "读取 Release 列表失败：$Repo"
$releaseExists = $false
foreach ($releaseTag in $releaseTags) {
  if ($releaseTag.tagName -eq $Version) {
    $releaseExists = $true
    break
  }
}

if ($releaseExists) {
  gh release edit $Version --repo $Repo --title "影视版-$Version" --notes-file $notesPath --latest
  Assert-LastExitCode "更新 Release 信息失败：$Version"
} else {
  gh release create $Version --repo $Repo --title "影视版-$Version" --notes-file $notesPath --latest
  Assert-LastExitCode "创建 Release 失败：$Version"
}

$release = gh api "repos/$Repo/releases/tags/$Version" | ConvertFrom-Json
Assert-LastExitCode "读取 Release 信息失败：$Version"

Remove-ReleaseAssetIfExists `
  -Release $release `
  -Names @($installerName, $localInstallerName, "update.json", "-.-$Version.exe")

$token = Get-GitHubToken
$installerAsset = Upload-ReleaseAsset `
  -ReleaseId $release.id `
  -FilePath $installerPath `
  -AssetName $installerName `
  -ContentType "application/x-msdownload" `
  -Token $token

$assetUrlName = ConvertTo-AssetUrlName $installerAsset.name
$installerUrl = "https://github.com/$Repo/releases/download/$Version/$assetUrlName"
$updateInfo = [ordered]@{
  version = $Version
  installerName = $installerName
  installerUrl = $installerUrl
  sha256 = $hash
  size = $fileInfo.Length
  publishedAt = $publishedAt
  releaseNotes = $ReleaseNotes
  mandatory = $Mandatory
}
$updateJsonContent = $updateInfo | ConvertTo-Json -Depth 4
Write-Utf8NoBomFile -Path $updateJsonPath -Content $updateJsonContent

Upload-ReleaseAsset `
  -ReleaseId $release.id `
  -FilePath $updateJsonPath `
  -AssetName "update.json" `
  -ContentType "application/json" `
  -Token $token `
  | Out-Null

Write-Host "已发布 GitHub Release：$Repo@$Version"
Write-Host "安装包：$installerName"
Write-Host "SHA256：$hash"
Write-Host "update.json：$updateJsonPath"





