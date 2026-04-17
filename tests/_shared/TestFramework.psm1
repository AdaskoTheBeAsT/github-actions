Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:TestFrameworkFailures = New-Object System.Collections.Generic.List[string]

function Reset-TestFramework {
  $script:TestFrameworkFailures = New-Object System.Collections.Generic.List[string]
}

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

function Assert-Match {
  param(
    [string]$Actual,
    [string]$Pattern,
    [string]$Message
  )

  if ($Actual -notmatch $Pattern) {
    throw "$Message Pattern '$Pattern' was not found."
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

function Assert-SequenceEqual {
  param(
    [string[]]$Actual,
    [string[]]$Expected,
    [string]$Message
  )

  $actualItems = @($Actual)
  $expectedItems = @($Expected)

  Assert-Equal -Actual $actualItems.Count -Expected $expectedItems.Count -Message $Message
  for ($i = 0; $i -lt $expectedItems.Count; $i++) {
    Assert-Equal -Actual $actualItems[$i] -Expected $expectedItems[$i] -Message $Message
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
    $script:TestFrameworkFailures.Add($message) | Out-Null
    Write-Host "[FAIL] $message"
  }
}

function Assert-TestFrameworkSuccess {
  if ($script:TestFrameworkFailures.Count -gt 0) {
    throw ("{0} test(s) failed.`n`n{1}" -f $script:TestFrameworkFailures.Count, ($script:TestFrameworkFailures -join "`n`n"))
  }

  Write-Host "All tests passed."
}

Export-ModuleMember -Function `
  Reset-TestFramework, `
  New-TestDirectory, `
  Assert-Equal, `
  Assert-True, `
  Assert-Match, `
  Assert-Throws, `
  Assert-SequenceEqual, `
  Invoke-TestCase, `
  Assert-TestFrameworkSuccess
