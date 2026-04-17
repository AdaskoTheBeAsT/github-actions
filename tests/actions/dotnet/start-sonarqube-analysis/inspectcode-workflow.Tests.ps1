Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$workflowPath = Join-Path $repoRoot ".github/workflows/dotnet-build-sonarqube-nuget.yml"
$workflowContent = Get-Content -LiteralPath $workflowPath -Raw

Import-Module -Force (Join-Path $repoRoot "tests/_shared/TestFramework.psm1")
Reset-TestFramework

Invoke-TestCase -Name "quotes the inspectcode output argument so PowerShell expands the report path" -ScriptBlock {
  Assert-True -Condition $workflowContent.Contains('"-o=$reportPath"') -Message 'The workflow should quote the -o=$reportPath argument for jb inspectcode.'
  Assert-True -Condition (-not ($workflowContent -match '(?m)^\s+-o=\$reportPath\s*$')) -Message 'The workflow should not pass the bare -o=$reportPath argument to jb inspectcode.'
}

Assert-TestFrameworkSuccess
