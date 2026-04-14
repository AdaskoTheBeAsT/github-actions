Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$scriptPath = Join-Path $repoRoot ".github/actions/dotnet/test-with-coverage/test-with-coverage.ps1"
$failures = New-Object System.Collections.Generic.List[string]

function New-TestDirectory {
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $path | Out-Null
  return $path
}

function Assert-Equal {
  param(
    $Actual,
    $Expected,
    [string]$Message
  )

  if ($Actual -ne $Expected) {
    throw "$Message Expected '$Expected', got '$Actual'."
  }
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Assert-Throws {
  param(
    [scriptblock]$ScriptBlock,
    [string]$Message
  )

  $didThrow = $false
  try {
    & $ScriptBlock
  } catch {
    $didThrow = $true
  }

  if (-not $didThrow) {
    throw $Message
  }
}

function Invoke-TestCase {
  param(
    [string]$Name,
    [scriptblock]$ScriptBlock
  )

  try {
    & $ScriptBlock
    Write-Host "[PASS] $Name"
  } catch {
    $message = "$Name`n$($_.Exception.Message)"
    $failures.Add($message) | Out-Null
    Write-Host "[FAIL] $message"
  }
}

Invoke-TestCase -Name "runs dotnet-coverage with the expected test command" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $global:CapturedCoverageArguments = @()

    function global:dotnet-coverage {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedCoverageArguments = @($Arguments)
    }

    & $scriptPath `
      -SolutionName "src/My Solution.sln" `
      -CoverageSettingsFile "config/coverage.settings.xml" `
      -Configuration "Debug" `
      -ResultsDirectory "Test Results" `
      -CoverageOutputFile "artifacts/coverage.xml"

    Assert-Equal -Actual $global:CapturedCoverageArguments[0] -Expected "collect" -Message "The first dotnet-coverage argument should be collect."
    Assert-True -Condition ($global:CapturedCoverageArguments[1] -like 'dotnet test "src/My Solution.sln"*') -Message "The test command should quote the solution path when it contains spaces."
    Assert-True -Condition ($global:CapturedCoverageArguments[1] -like '*--results-directory "Test Results"*') -Message "The results directory should be included in the generated test command."
    Assert-True -Condition ($global:CapturedCoverageArguments -contains "--settings") -Message "The coverage settings flag should be passed."
    Assert-True -Condition ($global:CapturedCoverageArguments -contains (Join-Path $workingDirectory "config\coverage.settings.xml")) -Message "The coverage settings file should be resolved from the workspace."
    Assert-True -Condition ($global:CapturedCoverageArguments -contains "artifacts/coverage.xml") -Message "The coverage output file should be passed through."
  } finally {
    Remove-Item Function:\global:dotnet-coverage -ErrorAction SilentlyContinue
    Remove-Variable CapturedCoverageArguments -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when the solution name is empty" -ScriptBlock {
  Assert-Throws -ScriptBlock {
    & $scriptPath -SolutionName " "
  } -Message "The script should fail when solution_name is empty."
}

if ($failures.Count -gt 0) {
  throw ("{0} test(s) failed.`n`n{1}" -f $failures.Count, ($failures -join "`n`n"))
}

Write-Host "All tests passed."
