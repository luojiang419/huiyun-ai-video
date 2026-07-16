param(
  [string]$Repo = "luojiang419/huiyun-ai-video-releases",
  [string]$MinimumVersion = "V10.0.1",
  [string]$SourceSha = "",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

function ConvertTo-VersionParts {
  param(
    [string]$Version,
    [bool]$AllowTwoParts = $false
  )

  $pattern = if ($AllowTwoParts) {
    '^[vV](?<major>\d+)\.(?<minor>\d+)(?:\.(?<patch>\d+))?$'
  } else {
    '^[vV](?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$'
  }
  $match = [regex]::Match($Version.Trim(), $pattern)
  if (-not $match.Success) {
    throw "无效稳定版本号：$Version"
  }
  $patch = if ($match.Groups['patch'].Success) {
    [int]$match.Groups['patch'].Value
  } else {
    0
  }
  return @(
    [int]$match.Groups['major'].Value,
    [int]$match.Groups['minor'].Value,
    $patch
  )
}

function Compare-VersionParts {
  param([int[]]$Left, [int[]]$Right)
  for ($index = 0; $index -lt 3; $index++) {
    if ($Left[$index] -lt $Right[$index]) { return -1 }
    if ($Left[$index] -gt $Right[$index]) { return 1 }
  }
  return 0
}

function Get-NextReleaseVersion {
  param([string]$LatestVersion, [string]$Minimum)

  $minimumParts = ConvertTo-VersionParts -Version $Minimum
  if ([string]::IsNullOrWhiteSpace($LatestVersion)) {
    return $Minimum
  }
  $latestParts = ConvertTo-VersionParts -Version $LatestVersion -AllowTwoParts $true
  $candidate = @($latestParts[0], $latestParts[1], ($latestParts[2] + 1))
  if ((Compare-VersionParts -Left $candidate -Right $minimumParts) -lt 0) {
    $candidate = $minimumParts
  }
  return "V$($candidate[0]).$($candidate[1]).$($candidate[2])"
}

function Assert-Equal {
  param([string]$Actual, [string]$Expected)
  if ($Actual -ne $Expected) {
    throw "自测失败：期望 $Expected，实际 $Actual"
  }
}

if ($SelfTest) {
  Assert-Equal (Get-NextReleaseVersion -LatestVersion "" -Minimum "V10.0.1") "V10.0.1"
  Assert-Equal (Get-NextReleaseVersion -LatestVersion "V10.0" -Minimum "V10.0.1") "V10.0.1"
  Assert-Equal (Get-NextReleaseVersion -LatestVersion "V10.0.1" -Minimum "V10.0.1") "V10.0.2"
  Assert-Equal (Get-NextReleaseVersion -LatestVersion "v12.3.9" -Minimum "V10.0.1") "V12.3.10"
  try {
    Get-NextReleaseVersion -LatestVersion "preview-1" -Minimum "V10.0.1" | Out-Null
    throw "自测失败：非法标签未被拒绝"
  } catch {
    if ($_.Exception.Message -like '自测失败*') { throw }
  }
  Write-Host "版本脚本自测通过"
  exit 0
}

$headers = @{
  Accept = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
}
$token = $env:RELEASES_REPO_TOKEN
if (-not [string]::IsNullOrWhiteSpace($token)) {
  $headers.Authorization = "Bearer $token"
}

$latest = $null
try {
  $latest = Invoke-RestMethod `
    -Uri "https://api.github.com/repos/$Repo/releases/latest" `
    -Headers $headers
} catch {
  if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
}

$skip = $false
if ($null -ne $latest -and -not [string]::IsNullOrWhiteSpace($SourceSha)) {
  $manifestAsset = @($latest.assets | Where-Object { $_.name -eq 'update.json' })
  if ($manifestAsset.Count -eq 1) {
    try {
      $manifest = Invoke-RestMethod -Uri $manifestAsset[0].browser_download_url -Headers $headers
      $skip = $manifest.sourceSha -eq $SourceSha
    } catch {
      $skip = $false
    }
  }
}

$latestTag = if ($null -eq $latest) { "" } else { [string]$latest.tag_name }
$version = Get-NextReleaseVersion -LatestVersion $latestTag -Minimum $MinimumVersion
$buildName = $version.Substring(1)

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
  "version=$version" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  "build_name=$buildName" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
  "skip=$($skip.ToString().ToLowerInvariant())" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}
Write-Host "latest=$latestTag version=$version skip=$skip"
