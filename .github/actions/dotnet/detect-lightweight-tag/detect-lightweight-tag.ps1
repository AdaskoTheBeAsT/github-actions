[CmdletBinding()]
param(
  [AllowEmptyString()]
  [string]$Ref = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EffectiveRef {
  param(
    [AllowEmptyString()]
    [string]$InputRef
  )

  if (-not [string]::IsNullOrWhiteSpace($InputRef)) {
    return $InputRef.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REF)) {
    return $env:GITHUB_REF.Trim()
  }

  throw "Git ref is empty."
}

function Set-GitHubOutputValue {
  param(
    [string]$Name,
    [string]$Value
  )

  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name=$Value"
  }
}

function Set-GitHubEnvironmentValue {
  param(
    [string]$Name,
    [string]$Value
  )

  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) {
    Add-Content -LiteralPath $env:GITHUB_ENV -Value "$Name=$Value"
  }
}

$effectiveRef = Get-EffectiveRef -InputRef $Ref
$isLightweightTag = "false"

if ($effectiveRef.StartsWith("refs/tags/", [System.StringComparison]::Ordinal)) {
  $tagName = $effectiveRef.Substring("refs/tags/".Length)
  if ([string]::IsNullOrWhiteSpace($tagName)) {
    throw "Tag name is empty in ref '$effectiveRef'."
  }

  $tagType = & git cat-file -t $tagName 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to resolve tag '$tagName'."
  }
  $tagType = "$tagType".Trim()

  Write-Host "Tag '$tagName' is type: $tagType"
  if ($tagType -eq "commit") {
    $isLightweightTag = "true"
  }
} else {
  Write-Host "Ref '$effectiveRef' is not a tag ref."
}

Set-GitHubEnvironmentValue -Name "IS_LIGHTWEIGHT_TAG" -Value $isLightweightTag
Set-GitHubOutputValue -Name "is_lightweight_tag" -Value $isLightweightTag
