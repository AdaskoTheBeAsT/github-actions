[CmdletBinding()]
param(
  [AllowEmptyString()]
  [string]$DotnetVersions = "",

  [AllowEmptyString()]
  [string]$UseGlobalJson = "false",

  [AllowEmptyString()]
  [string]$RunnerType = "auto"
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

function Get-WorkspacePath {
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
    return $env:GITHUB_WORKSPACE.Trim()
  }

  return (Get-Location).Path
}

function Get-ResolvedRunnerType {
  param(
    [AllowEmptyString()]
    [string]$RequestedRunnerType
  )

  $normalizedRunnerType = $RequestedRunnerType.Trim().ToLowerInvariant()
  if ($normalizedRunnerType -notin @("auto", "vstest", "mtp")) {
    throw "Input 'runner_type' must be one of: auto, vstest, mtp."
  }

  if ($normalizedRunnerType -ne "auto") {
    return $normalizedRunnerType
  }

  $globalJsonPath = Join-Path (Get-WorkspacePath) "global.json"
  if (-not (Test-Path -LiteralPath $globalJsonPath -PathType Leaf)) {
    return "vstest"
  }

  try {
    $globalJson = Get-Content -LiteralPath $globalJsonPath -Raw | ConvertFrom-Json
  } catch {
    throw "Failed to read test runner from '$globalJsonPath': $($_.Exception.Message)"
  }

  $testProperty = $globalJson.PSObject.Properties["test"]
  $runnerProperty = if ($null -ne $testProperty -and $null -ne $testProperty.Value) {
    $testProperty.Value.PSObject.Properties["runner"]
  } else {
    $null
  }

  if ($null -ne $runnerProperty -and
      -not [string]::IsNullOrWhiteSpace([string]$runnerProperty.Value) -and
      ([string]$runnerProperty.Value).Equals(
        "Microsoft.Testing.Platform",
        [System.StringComparison]::OrdinalIgnoreCase
      )) {
    return "mtp"
  }

  return "vstest"
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
$resolvedRunnerType = Get-ResolvedRunnerType -RequestedRunnerType $RunnerType
$globalJsonFile = ""
if (Test-InputIsTrue -Value $UseGlobalJson) {
  $globalJsonFile = "global.json"
}

if ($versions.Count -eq 0 -and [string]::IsNullOrWhiteSpace($globalJsonFile)) {
  throw "Either 'dotnet_versions' must be provided or 'use_global_json' must be 'true'."
}

Set-GitHubOutputValues -Name "versions" -Values $versions
Set-GitHubOutputValue -Name "global_json_file" -Value $globalJsonFile
Set-GitHubOutputValue -Name "runner_type" -Value $resolvedRunnerType

$resolvedSources = New-Object System.Collections.Generic.List[string]
if ($versions.Count -gt 0) {
  $resolvedSources.Add("versions=$($versions -join ', ')") | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($globalJsonFile)) {
  $resolvedSources.Add("global_json_file=$globalJsonFile") | Out-Null
}

Write-Host "Resolved setup-dotnet inputs: $($resolvedSources -join '; ')"
Write-Host "Resolved test runner: $resolvedRunnerType"
