Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$scriptPath = Join-Path $repoRoot ".github/actions/dotnet/publish-nuget-packages/publish-nuget-packages.ps1"
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

Invoke-TestCase -Name "publishes only regular NuGet packages" -ScriptBlock {
  $workingDirectory = New-TestDirectory
  $outputDirectory = Join-Path $workingDirectory "artifacts\nuget"

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $global:CapturedDotnetCalls = New-Object System.Collections.Generic.List[string[]]
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.1.0.0.nupkg") | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.1.0.0.snupkg") | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.1.0.0.symbols.nupkg") | Out-Null

    function global:dotnet {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedDotnetCalls.Add(@($Arguments)) | Out-Null
    }

    & $scriptPath `
      -PackageOutputDirectory "artifacts/nuget" `
      -NugetSourceUrl "https://api.nuget.org/v3/index.json" `
      -NugetApiKey "api-key"

    Assert-Equal -Actual $global:CapturedDotnetCalls.Count -Expected 1 -Message "Only publishable packages should be pushed."
    Assert-True -Condition ($global:CapturedDotnetCalls[0] -contains "nuget") -Message "The dotnet nuget command was not used."
    Assert-True -Condition ($global:CapturedDotnetCalls[0] -contains "push") -Message "The dotnet nuget push command was not used."
    Assert-True -Condition ($global:CapturedDotnetCalls[0] -contains (Join-Path $outputDirectory "Library.1.0.0.nupkg")) -Message "The regular package should be pushed."
    Assert-True -Condition (-not ($global:CapturedDotnetCalls[0] -contains (Join-Path $outputDirectory "Library.1.0.0.snupkg"))) -Message "The symbols package should not be pushed."
  } finally {
    Remove-Item Function:\global:dotnet -ErrorAction SilentlyContinue
    Remove-Variable CapturedDotnetCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when no publishable packages are found" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    New-Item -ItemType Directory -Path (Join-Path $workingDirectory "artifacts\nuget") | Out-Null

    Assert-Throws -ScriptBlock {
      & $scriptPath `
        -PackageOutputDirectory "artifacts/nuget" `
        -NugetSourceUrl "https://api.nuget.org/v3/index.json" `
        -NugetApiKey "api-key"
    } -Message "The script should fail when no publishable packages are present."
  } finally {
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

if ($failures.Count -gt 0) {
  throw ("{0} test(s) failed.`n`n{1}" -f $failures.Count, ($failures -join "`n`n"))
}

Write-Host "All tests passed."
