[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SolutionName,

  [string]$CoverageSettingsFile = "coverage.settings.xml",

  [string]$Configuration = "Debug",

  [string]$ResultsDirectory = "TestResults",

  [string]$CoverageOutputFile = "coverage.xml",

  [AllowEmptyString()]
  [string]$TestFrameworks = "",

  [string]$RunnerType = "vstest"
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

function Test-NuGetPackageResolved {
  param(
    [string]$PackageId
  )

  $packagePrefix = "$PackageId/"
  $assetsFiles = Get-ChildItem `
    -LiteralPath (Get-WorkspacePath) `
    -Filter "project.assets.json" `
    -File `
    -Recurse `
    -ErrorAction SilentlyContinue

  foreach ($assetsFile in $assetsFiles) {
    try {
      $assets = Get-Content -LiteralPath $assetsFile.FullName -Raw | ConvertFrom-Json
    } catch {
      Write-Warning "Could not inspect NuGet assets file '$($assetsFile.FullName)': $($_.Exception.Message)"
      continue
    }

    $librariesProperty = $assets.PSObject.Properties["libraries"]
    if ($null -eq $librariesProperty -or $null -eq $librariesProperty.Value) {
      continue
    }

    foreach ($library in $librariesProperty.Value.PSObject.Properties) {
      if ($library.Name.StartsWith($packagePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
      }
    }
  }

  return $false
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

function Set-TestEnvironmentVariable {
  param(
    [AllowNull()]
    [AllowEmptyString()]
    [string]$Payload,

    [Parameter(Mandatory = $true)]
    [string]$Source,

    [switch]$Mask
  )

  if ([string]::IsNullOrWhiteSpace($Payload)) {
    return
  }

  foreach ($line in ($Payload -split "`r?`n")) {
    $entry = $line.Trim()

    if ([string]::IsNullOrWhiteSpace($entry) -or $entry.StartsWith("#")) {
      continue
    }

    $separatorIndex = $entry.IndexOf("=")
    if ($separatorIndex -lt 1) {
      throw "Input '$Source' contains an entry that is not in NAME=VALUE format."
    }

    $name = $entry.Substring(0, $separatorIndex).Trim()
    $value = $entry.Substring($separatorIndex + 1).Trim()

    if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
      throw "Input '$Source' contains an invalid environment variable name '$name'."
    }

    # A secret handed to the workflow is masked as one blob, so every value parsed out of it needs its own mask.
    if ($Mask -and -not [string]::IsNullOrWhiteSpace($value)) {
      Write-Host "::add-mask::$value"
    }

    Write-Host "Setting environment variable '$name' from '$Source' for the test run."
    Set-Item -LiteralPath "Env:\$name" -Value $value
  }
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

function Merge-CoverageFiles {
  param(
    [string[]]$CoverageFiles,
    [string]$CoverageOutput
  )

  if ($CoverageFiles.Count -eq 0) {
    throw "No coverage files were generated."
  }

  Write-Host "Merging coverage from $($CoverageFiles.Count) test run(s)."
  $mergeArguments = @("merge") + $CoverageFiles + @(
    "-o", $CoverageOutput,
    "-f", "xml"
  )
  & dotnet-coverage @mergeArguments
  if ($LASTEXITCODE -ne 0) {
    throw "dotnet-coverage merge exited with code $LASTEXITCODE"
  }
}

Assert-NotWhiteSpace -Value $SolutionName -Name "solution_name"
Assert-NotWhiteSpace -Value $CoverageSettingsFile -Name "coverage_settings_file"
Assert-NotWhiteSpace -Value $Configuration -Name "configuration"
Assert-NotWhiteSpace -Value $ResultsDirectory -Name "results_directory"
Assert-NotWhiteSpace -Value $CoverageOutputFile -Name "coverage_output_file"
Assert-NotWhiteSpace -Value $RunnerType -Name "runner_type"

$normalizedRunnerType = $RunnerType.Trim().ToLowerInvariant()
if ($normalizedRunnerType -notin @("vstest", "mtp")) {
  throw "Input 'runner_type' must be either 'vstest' or 'mtp'."
}

Set-TestEnvironmentVariable `
  -Payload ([System.Environment]::GetEnvironmentVariable("TEST_ENV_VARS")) `
  -Source "env_vars"

Set-TestEnvironmentVariable `
  -Payload ([System.Environment]::GetEnvironmentVariable("TEST_ENV_SECRETS")) `
  -Source "env_secrets" `
  -Mask

# The raw payloads are not meant to reach the test process itself.
Remove-Item Env:\TEST_ENV_VARS -ErrorAction SilentlyContinue
Remove-Item Env:\TEST_ENV_SECRETS -ErrorAction SilentlyContinue

$coverageSettingsPath = Resolve-WorkspaceRelativePath -Path $CoverageSettingsFile

$frameworks = @()
if (-not [string]::IsNullOrWhiteSpace($TestFrameworks)) {
  $frameworks = $TestFrameworks.Split(',') |
    ForEach-Object { $_.Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

$commonTestArgs = @(
  "--no-restore",
  "--no-build",
  "--configuration", $Configuration,
  "--results-directory", $ResultsDirectory,
  "-p:TreatWarningsAsErrors=false",
  "-p:TestTfmsInParallel=false"
)

$runnerDisplayName = if ($normalizedRunnerType -eq "vstest") {
  "VSTest"
} else {
  "Microsoft Testing Platform"
}

$baseTestArgs = if ($normalizedRunnerType -eq "vstest") {
  @(
    $SolutionName
  ) + $commonTestArgs + @(
    "--logger", "trx"
  )
} else {
  @(
    "--solution", $SolutionName
  ) + $commonTestArgs + @(
    "--report-xunit-trx"
  )
}

if ($normalizedRunnerType -eq "mtp" -and
    $env:GITHUB_ACTIONS -eq "true" -and
    (Test-NuGetPackageResolved -PackageId "Microsoft.Testing.Extensions.GitHubActionsReport")) {
  Write-Host "Microsoft.Testing.Extensions.GitHubActionsReport detected; enabling the GitHub Actions report."
  $baseTestArgs += "--report-gh"
}

if ($frameworks.Count -eq 0) {
  Write-Host "Running $runnerDisplayName tests with coverage for all TFMs."
  Invoke-DotnetCoverage `
    -DotnetTestArgs $baseTestArgs `
    -CoverageOutput $CoverageOutputFile `
    -CoverageOutputFormat "xml" `
    -CoverageSettingsPath $coverageSettingsPath
  return
}

Write-Host "Running $runnerDisplayName tests with coverage for TFMs: $($frameworks -join ', ')"

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

Merge-CoverageFiles `
  -CoverageFiles $intermediateFiles `
  -CoverageOutput $CoverageOutputFile
