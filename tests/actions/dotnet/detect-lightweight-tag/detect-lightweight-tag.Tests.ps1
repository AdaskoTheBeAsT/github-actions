Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$scriptPath = Join-Path $repoRoot ".github/actions/dotnet/detect-lightweight-tag/detect-lightweight-tag.ps1"
$failures = New-Object System.Collections.Generic.List[string]

function New-TestDirectory {
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $path | Out-Null
  return $path
}

function Initialize-GitRepository {
  $path = New-TestDirectory

  Push-Location $path
  try {
    & git init | Out-Null
    & git config user.email "test@example.com"
    & git config user.name "Test User"

    Set-Content -LiteralPath (Join-Path $path "README.md") -Value "test" -Encoding utf8NoBOM
    & git add README.md
    & git commit -m "Initial commit" | Out-Null
  } finally {
    Pop-Location
  }

  return $path
}

function Get-FileVariableValue {
  param(
    [string]$Path,
    [string]$Name
  )

  $prefix = "$Name="
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
      return $line.Substring($prefix.Length)
    }
  }

  throw "Variable '$Name' was not found in '$Path'."
}

function Invoke-DetectLightweightTagScript {
  param(
    [string]$WorkingDirectory,
    [AllowEmptyString()]
    [string]$Ref = "",
    [AllowEmptyString()]
    [string]$GitHubRef = ""
  )

  $outputPath = Join-Path $WorkingDirectory "github_output.txt"
  $envPath = Join-Path $WorkingDirectory "github_env.txt"

  Push-Location $WorkingDirectory
  try {
    $env:GITHUB_OUTPUT = $outputPath
    $env:GITHUB_ENV = $envPath

    if ([string]::IsNullOrWhiteSpace($GitHubRef)) {
      Remove-Item Env:GITHUB_REF -ErrorAction SilentlyContinue
    } else {
      $env:GITHUB_REF = $GitHubRef
    }

    if ([string]::IsNullOrWhiteSpace($Ref)) {
      & $scriptPath
    } else {
      & $scriptPath -Ref $Ref
    }
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_ENV -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_REF -ErrorAction SilentlyContinue
    Pop-Location
  }

  return @{
    OutputPath = $outputPath
    EnvPath = $envPath
  }
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

Invoke-TestCase -Name "detects a lightweight tag" -ScriptBlock {
  $repoPath = Initialize-GitRepository

  try {
    Push-Location $repoPath
    try {
      & git tag "v1.0.0"
    } finally {
      Pop-Location
    }

    $result = Invoke-DetectLightweightTagScript -WorkingDirectory $repoPath -Ref "refs/tags/v1.0.0"

    Assert-Equal -Actual (Get-FileVariableValue -Path $result.OutputPath -Name "is_lightweight_tag") -Expected "true" -Message "The output value should indicate a lightweight tag."
    Assert-Equal -Actual (Get-FileVariableValue -Path $result.EnvPath -Name "IS_LIGHTWEIGHT_TAG") -Expected "true" -Message "The environment value should indicate a lightweight tag."
  } finally {
    Remove-Item -LiteralPath $repoPath -Recurse -Force
  }
}

Invoke-TestCase -Name "detects an annotated tag" -ScriptBlock {
  $repoPath = Initialize-GitRepository

  try {
    Push-Location $repoPath
    try {
      & git tag -a "v1.0.1" -m "annotated"
    } finally {
      Pop-Location
    }

    $result = Invoke-DetectLightweightTagScript -WorkingDirectory $repoPath -Ref "refs/tags/v1.0.1"

    Assert-Equal -Actual (Get-FileVariableValue -Path $result.OutputPath -Name "is_lightweight_tag") -Expected "false" -Message "The output value should indicate an annotated tag."
    Assert-Equal -Actual (Get-FileVariableValue -Path $result.EnvPath -Name "IS_LIGHTWEIGHT_TAG") -Expected "false" -Message "The environment value should indicate an annotated tag."
  } finally {
    Remove-Item -LiteralPath $repoPath -Recurse -Force
  }
}

Invoke-TestCase -Name "returns false for a non-tag ref" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $result = Invoke-DetectLightweightTagScript -WorkingDirectory $workingDirectory -Ref "refs/heads/main"

    Assert-Equal -Actual (Get-FileVariableValue -Path $result.OutputPath -Name "is_lightweight_tag") -Expected "false" -Message "Non-tag refs should return false."
    Assert-Equal -Actual (Get-FileVariableValue -Path $result.EnvPath -Name "IS_LIGHTWEIGHT_TAG") -Expected "false" -Message "Non-tag refs should write false to GITHUB_ENV."
  } finally {
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "uses GITHUB_REF when ref input is not provided" -ScriptBlock {
  $repoPath = Initialize-GitRepository

  try {
    Push-Location $repoPath
    try {
      & git tag "v2.0.0"
    } finally {
      Pop-Location
    }

    $result = Invoke-DetectLightweightTagScript -WorkingDirectory $repoPath -GitHubRef "refs/tags/v2.0.0"

    Assert-Equal -Actual (Get-FileVariableValue -Path $result.OutputPath -Name "is_lightweight_tag") -Expected "true" -Message "The script should fall back to GITHUB_REF."
  } finally {
    Remove-Item -LiteralPath $repoPath -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when no git ref is available" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    Assert-Throws -ScriptBlock { Invoke-DetectLightweightTagScript -WorkingDirectory $workingDirectory } -Message "The script should fail when no ref is provided."
  } finally {
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

if ($failures.Count -gt 0) {
  throw ("{0} test(s) failed.`n`n{1}" -f $failures.Count, ($failures -join "`n`n"))
}

Write-Host "All tests passed."
