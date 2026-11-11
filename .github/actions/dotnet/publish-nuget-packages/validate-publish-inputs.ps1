[CmdletBinding()]
param(
  [AllowEmptyString()]
  [string]$PackageOutputDirectory = "artifacts/nuget",

  [AllowEmptyString()]
  [string]$ArtifactName = "",

  [AllowEmptyString()]
  [string]$NugetSourceUrl = "https://api.nuget.org/v3/index.json",

  [AllowEmptyString()]
  [string]$NugetUser = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-NotWhiteSpace {
  param(
    [AllowNull()]
    [string]$Value,
    [string]$Name
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Input '$Name' is required."
  }
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

Assert-NotWhiteSpace -Value $PackageOutputDirectory -Name "package_output_directory"
Assert-NotWhiteSpace -Value $NugetSourceUrl -Name "nuget_source_url"

$hasNugetUser = -not [string]::IsNullOrWhiteSpace($NugetUser)
$hasNugetApiKey = -not [string]::IsNullOrWhiteSpace($env:INPUT_NUGET_API_KEY)

if (-not $hasNugetUser -and -not $hasNugetApiKey) {
  throw "Either input 'nuget_user' (for OIDC Trusted Publishing) or 'nuget_api_key' must be provided."
}

if ($hasNugetUser -and $hasNugetApiKey) {
  throw "Provide either 'nuget_user' or 'nuget_api_key', not both."
}

$trimmedArtifactName = if ([string]::IsNullOrWhiteSpace($ArtifactName)) { "" } else { $ArtifactName.Trim() }
$downloadArtifact = if ($trimmedArtifactName.Length -gt 0) { "true" } else { "false" }
$useTrustedPublishing = if ($hasNugetUser) { "true" } else { "false" }
$trimmedNugetUser = if ($hasNugetUser) { $NugetUser.Trim() } else { "" }

Set-GitHubOutputValue -Name "download_artifact" -Value $downloadArtifact
Set-GitHubOutputValue -Name "artifact_name" -Value $trimmedArtifactName
Set-GitHubOutputValue -Name "use_trusted_publishing" -Value $useTrustedPublishing
Set-GitHubOutputValue -Name "nuget_user" -Value $trimmedNugetUser
