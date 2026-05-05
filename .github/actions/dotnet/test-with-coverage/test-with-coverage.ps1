[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SolutionName,

  [string]$CoverageSettingsFile = "coverage.settings.xml",

  [string]$Configuration = "Debug",

  [string]$ResultsDirectory = "TestResults",

  [string]$CoverageOutputFile = "coverage.xml",

  [AllowEmptyString()]
  [string]$TestFrameworks = ""
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

function Invoke-DotnetCoverage {
  param(
    [string[]]$DotnetTestArgs,
    [string]$CoverageOutput,
    [string]$CoverageOutputFormat,
    [string]$CoverageSettingsPath
  )

  $testCommand = (@("dotnet", "test") + $DotnetTestArgs |
    ForEach-Object { Convert-ToCommandArgument -Value $_ }) -join " "

  $coverageArguments = @(
    "collect",
    $testCommand,
    "--settings", $CoverageSettingsPath,
    "-f", $CoverageOutputFormat,
    "-o", $CoverageOutput
  )

  Write-Host "Running: dotnet-coverage $($coverageArguments -join ' ')"
  & dotnet-coverage @coverageArguments
  if ($LASTEXITCODE -ne 0) {
    throw "dotnet-coverage exited with code $LASTEXITCODE"
  }
}

Assert-NotWhiteSpace -Value $SolutionName -Name "solution_name"
Assert-NotWhiteSpace -Value $CoverageSettingsFile -Name "coverage_settings_file"
Assert-NotWhiteSpace -Value $Configuration -Name "configuration"
Assert-NotWhiteSpace -Value $ResultsDirectory -Name "results_directory"
Assert-NotWhiteSpace -Value $CoverageOutputFile -Name "coverage_output_file"

$coverageSettingsPath = Resolve-WorkspaceRelativePath -Path $CoverageSettingsFile

$frameworks = @()
if (-not [string]::IsNullOrWhiteSpace($TestFrameworks)) {
  $frameworks = $TestFrameworks.Split(',') |
    ForEach-Object { $_.Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

$baseTestArgs = @(
  $SolutionName,
  "--no-restore",
  "--no-build",
  "--configuration", $Configuration,
  "--logger", "trx",
  "--results-directory", $ResultsDirectory,
  "-p:TreatWarningsAsErrors=false",
  "-p:TestTfmsInParallel=false"
)

if ($frameworks.Count -eq 0) {
  Write-Host "Running tests with coverage for all TFMs."
  Invoke-DotnetCoverage `
    -DotnetTestArgs $baseTestArgs `
    -CoverageOutput $CoverageOutputFile `
    -CoverageOutputFormat "xml" `
    -CoverageSettingsPath $coverageSettingsPath
  return
}

Write-Host "Running tests with coverage for TFMs: $($frameworks -join ', ')"

$intermediateDir = Join-Path (Get-WorkspacePath) "coverage-intermediate"
New-Item -ItemType Directory -Force -Path $intermediateDir | Out-Null

$intermediateFiles = @()
foreach ($tfm in $frameworks) {
  $intermediateFile = Join-Path $intermediateDir "$tfm.coverage"
  $tfmArgs = $baseTestArgs + @("-f", $tfm)

  Invoke-DotnetCoverage `
    -DotnetTestArgs $tfmArgs `
    -CoverageOutput $intermediateFile `
    -CoverageOutputFormat "coverage" `
    -CoverageSettingsPath $coverageSettingsPath

  $intermediateFiles += $intermediateFile
}

Write-Host "Merging coverage from $($intermediateFiles.Count) framework(s)."
$mergeArguments = @("merge") + $intermediateFiles + @(
  "-o", $CoverageOutputFile,
  "-f", "xml"
)
& dotnet-coverage @mergeArguments
if ($LASTEXITCODE -ne 0) {
  throw "dotnet-coverage merge exited with code $LASTEXITCODE"
}
