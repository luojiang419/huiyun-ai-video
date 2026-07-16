param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$InstallerPath,
  [Parameter(Mandatory = $true)][string]$ManifestPath,
  [Parameter(Mandatory = $true)][string]$ChecksumPath,
  [Parameter(Mandatory = $true)][string]$NotesPath,
  [Parameter(Mandatory = $true)][string]$SourceSha,
  [string]$Repo = "luojiang419/huiyun-ai-video-releases",
  [string]$SourceRepoRoot = "."
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
  throw "缺少 GH_TOKEN，无法发布到 $Repo"
}

function Invoke-Gh {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  & gh @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "gh 命令失败：gh $($Arguments -join ' ')"
  }
}

function Get-ReleaseOrNull {
  try {
    $raw = & gh api "repos/$Repo/releases?per_page=100" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $matches = @(($raw | ConvertFrom-Json) | Where-Object {
      $_.tag_name -ceq $Version
    })
    if ($matches.Count -gt 1) {
      throw "发现多个同标签 Release：$Version"
    }
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
  } catch {
    if ($_.Exception.Message -like '发现多个同标签*') { throw }
    return $null
  }
}

function Wait-Release {
  param([int]$Attempts = 10)
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $release = Get-ReleaseOrNull
    if ($null -ne $release) { return $release }
    if ($attempt -lt $Attempts) { Start-Sleep -Seconds 2 }
  }
  return $null
}

function Wait-LatestRelease {
  param([int]$Attempts = 10)
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      $candidate = (& gh api "repos/$Repo/releases/latest") | ConvertFrom-Json
      if ($LASTEXITCODE -eq 0 -and
          $candidate.tag_name -eq $Version -and
          -not $candidate.draft -and
          -not $candidate.prerelease) {
        return $candidate
      }
    } catch {
      # Retry eventual consistency after publishing the draft.
    }
    if ($attempt -lt $Attempts) { Start-Sleep -Seconds 2 }
  }
  return $null
}

function Assert-RemoteAssets {
  param([object]$Release)
  $expected = @(
    @{ Name = (Split-Path -Leaf $InstallerPath); Path = $InstallerPath },
    @{ Name = (Split-Path -Leaf $ManifestPath); Path = $ManifestPath },
    @{ Name = (Split-Path -Leaf $ChecksumPath); Path = $ChecksumPath }
  )
  foreach ($item in $expected) {
    $matches = @($Release.assets | Where-Object { $_.name -ceq $item.Name })
    if ($matches.Count -ne 1) {
      throw "远端资产必须唯一存在：$($item.Name)"
    }
    $localFile = Get-Item -LiteralPath $item.Path
    if ($matches[0].state -ne 'uploaded' -or
        [int64]$matches[0].size -ne $localFile.Length) {
      throw "远端资产状态或大小无效：$($item.Name)"
    }
    $localHash = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($matches[0].digest) -and
        $matches[0].digest -ne "sha256:$localHash") {
      throw "远端资产摘要不一致：$($item.Name)"
    }
  }
}

$createdDraft = $false
$createdSourceTag = $false
try {
  $existing = Get-ReleaseOrNull
  if ($null -ne $existing) {
    if (-not $existing.draft) {
      throw "版本 $Version 已存在正式 Release，拒绝覆盖"
    }
    Invoke-Gh release delete $Version --repo $Repo --yes --cleanup-tag
  }

  Invoke-Gh release create $Version `
    --repo $Repo `
    --target main `
    --title "绘云AI 影视版 $Version" `
    --notes-file $NotesPath `
    --draft
  $createdDraft = $true

  Invoke-Gh release upload $Version `
    $InstallerPath $ManifestPath $ChecksumPath `
    --repo $Repo `
    --clobber

  $draft = Wait-Release
  if ($null -eq $draft -or -not $draft.draft -or $draft.prerelease) {
    throw "Draft Release 状态异常"
  }
  Assert-RemoteAssets -Release $draft

  Push-Location $SourceRepoRoot
  try {
    $remoteTagLine = git ls-remote --tags origin "refs/tags/$Version"
    if ([string]::IsNullOrWhiteSpace($remoteTagLine)) {
      git tag $Version $SourceSha
      if ($LASTEXITCODE -ne 0) { throw "创建源码标签失败" }
      git push origin "refs/tags/$Version"
      if ($LASTEXITCODE -ne 0) { throw "推送源码标签失败" }
      $createdSourceTag = $true
    } else {
      $remoteSha = ($remoteTagLine -split '\s+')[0]
      $peeled = git ls-remote --tags origin "refs/tags/$Version^{}"
      if (-not [string]::IsNullOrWhiteSpace($peeled)) {
        $remoteSha = ($peeled -split '\s+')[0]
      }
      if ($remoteSha -ne $SourceSha) {
        throw "远端源码标签 $Version 未指向当前提交"
      }
    }
  } finally {
    Pop-Location
  }

  Invoke-Gh release edit $Version --repo $Repo --draft=false --latest
  $latest = Wait-LatestRelease
  if ($null -eq $latest) {
    throw "Latest Release 未指向 $Version"
  }
  Assert-RemoteAssets -Release $latest
  $publicManifestAsset = @($latest.assets | Where-Object { $_.name -eq 'update.json' })[0]
  $publicManifest = $null
  for ($attempt = 1; $attempt -le 10; $attempt++) {
    try {
      $publicManifest = Invoke-RestMethod -Uri $publicManifestAsset.browser_download_url
      break
    } catch {
      if ($attempt -lt 10) { Start-Sleep -Seconds 2 }
    }
  }
  if ($null -eq $publicManifest) { throw "公开 update.json 下载失败" }
  if ($publicManifest.version -ne $Version -or
      $publicManifest.sourceSha -ne $SourceSha -or
      $publicManifest.sha256 -ne (Get-FileHash $InstallerPath -Algorithm SHA256).Hash) {
    throw "公开 update.json 与本地构建不一致"
  }
  Write-Host "正式 Release 发布并远端复核成功：$($latest.html_url)"
} catch {
  if ($createdDraft) {
    $release = Wait-Release -Attempts 3
    if ($null -ne $release -and $release.draft) {
      & gh release delete $Version --repo $Repo --yes --cleanup-tag 2>$null
    }
  }
  if ($createdSourceTag) {
    Push-Location $SourceRepoRoot
    try {
      & git push origin ":refs/tags/$Version" 2>$null
      & git tag -d $Version 2>$null
    } finally {
      Pop-Location
    }
  }
  throw
}
