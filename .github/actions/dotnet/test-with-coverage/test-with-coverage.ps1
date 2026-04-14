[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SolutionName,

  [string]$CoverageSettingsFile = "coverage.settings.xml",

  [string]$Configuration = "Debug",

  [string]$ResultsDirectory = "TestResults",

  [string]$CoverageOutputFile = "coverage.xml"
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

function Get-WorkspacePath {
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
    return $env:GITHUB_WORKSPACE.Trim()
  }

  return (Get-Location).Path
}

function Resolve-WorkspaceRelativePath {
  param(
    [string]$Path
  )

  Assert-NotWhiteSpace -Value $Path -Name "path"

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return (Join-Path (Get-WorkspacePath) $Path)
}

function Convert-ToCommandArgument {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ($null -eq $Value) {
    return '""'
  }

  if ($Value -match '[\s"]') {
    return '"' + ($Value -replace '"', '\"') + '"'
  }

  return $Value
}

Assert-NotWhiteSpace -Value $SolutionName -Name "solution_name"
Assert-NotWhiteSpace -Value $CoverageSettingsFile -Name "coverage_settings_file"
Assert-NotWhiteSpace -Value $Configuration -Name "configuration"
Assert-NotWhiteSpace -Value $ResultsDirectory -Name "results_directory"
Assert-NotWhiteSpace -Value $CoverageOutputFile -Name "coverage_output_file"

$coverageSettingsPath = Resolve-WorkspaceRelativePath -Path $CoverageSettingsFile
$testCommandArguments = @(
  "dotnet",
  "test",
  $SolutionName,
  "--no-restore",
  "--no-build",
  "--configuration",
  $Configuration,
  "--logger",
  "trx",
  "--results-directory",
  $ResultsDirectory,
  "-p:TreatWarningsAsErrors=false",
  "-p:TestTfmsInParallel=false"
)
$testCommand = ($testCommandArguments | ForEach-Object { Convert-ToCommandArgument -Value $_ }) -join " "
$coverageArguments = @(
  "collect",
  $testCommand,
  "--settings",
  $coverageSettingsPath,
  "-f",
  "xml",
  "-o",
  $CoverageOutputFile
)

Write-Host "Running tests with coverage."
& dotnet-coverage @coverageArguments
