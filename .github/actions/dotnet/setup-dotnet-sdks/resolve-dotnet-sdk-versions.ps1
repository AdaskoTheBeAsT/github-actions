[CmdletBinding()]
param(
  [AllowEmptyString()]
  [string]$DotnetVersions = "",

  [AllowEmptyString()]
  [string]$UseGlobalJson = "false"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-InputIsTrue {
  param(
    [AllowNull()]
    [string]$Value
  )

  return $null -ne $Value -and $Value.Trim().Equals("true", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-NormalizedDotnetVersions {
  param(
    [AllowEmptyString()]
    [string]$MultipleVersions
  )

  if ([string]::IsNullOrWhiteSpace($MultipleVersions)) {
    return @()
  }

  $versions = @(
    $MultipleVersions.Split(",") |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )

  if ($versions.Count -eq 0) {
    throw "No valid .NET SDK versions were provided."
  }

  return $versions
}

function Set-GitHubOutputValue {
  param(
    [string]$Name,
    [string]$Value
  )

  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name=$Value"
}

function Set-GitHubOutputValues {
  param(
    [string]$Name,
    [string[]]$Values
  )

  if ($Values.Count -eq 0) {
    Set-GitHubOutputValue -Name $Name -Value ""
    return
  }

  $delimiter = "${Name}_$([System.Guid]::NewGuid().ToString('N'))"
  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name<<$delimiter"
  foreach ($value in $Values) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value $value
  }
  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value $delimiter
}

if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
  throw "GITHUB_OUTPUT is not set."
}

$versions = @(Get-NormalizedDotnetVersions -MultipleVersions $DotnetVersions)
$globalJsonFile = ""
if (Test-InputIsTrue -Value $UseGlobalJson) {
  $globalJsonFile = "global.json"
}

if ($versions.Count -eq 0 -and [string]::IsNullOrWhiteSpace($globalJsonFile)) {
  throw "Either 'dotnet_versions' must be provided or 'use_global_json' must be 'true'."
}

Set-GitHubOutputValues -Name "versions" -Values $versions
Set-GitHubOutputValue -Name "global_json_file" -Value $globalJsonFile

$resolvedSources = New-Object System.Collections.Generic.List[string]
if ($versions.Count -gt 0) {
  $resolvedSources.Add("versions=$($versions -join ', ')") | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($globalJsonFile)) {
  $resolvedSources.Add("global_json_file=$globalJsonFile") | Out-Null
}

Write-Host "Resolved setup-dotnet inputs: $($resolvedSources -join '; ')"
