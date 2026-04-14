Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$workflowPath = Join-Path $repoRoot ".github/workflows/dotnet-build-sonarqube-nuget.yml"
$workflowContent = Get-Content -LiteralPath $workflowPath -Raw
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
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

Invoke-TestCase -Name "quotes the inspectcode output argument so PowerShell expands the report path" -ScriptBlock {
  Assert-True -Condition $workflowContent.Contains('"-o=$reportPath"') -Message 'The workflow should quote the -o=$reportPath argument for jb inspectcode.'
  Assert-True -Condition (-not ($workflowContent -match '(?m)^\s+-o=\$reportPath\s*$')) -Message 'The workflow should not pass the bare -o=$reportPath argument to jb inspectcode.'
}

if ($failures.Count -gt 0) {
  throw ("{0} test(s) failed.`n`n{1}" -f $failures.Count, ($failures -join "`n`n"))
}

Write-Host "All tests passed."
