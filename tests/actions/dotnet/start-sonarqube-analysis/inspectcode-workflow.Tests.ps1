Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$workflowPath = Join-Path $repoRoot ".github/workflows/dotnet-build-sonarqube-nuget.yml"
$workflowContent = Get-Content -LiteralPath $workflowPath -Raw

Import-Module -Force (Join-Path $repoRoot "tests/_shared/TestFramework.psm1")
Reset-TestFramework

$step = [regex]::Match($workflowContent, '(?m)^      - name: Run ReSharper InspectCode\r?\n(?<body>(?:^ {8}.*\r?\n|^\r?\n)+)')
$run = [regex]::Match($step.Groups["body"].Value, '(?ms)^        run: \|\r?\n(?<script>.+)$')
Assert-True -Condition $run.Success -Message "The workflow should define a PowerShell InspectCode step."
$inspectCodeScript = [scriptblock]::Create(($run.Groups["script"].Value -replace '(?m)^ {10}', ''))

function Get-InspectCodeArguments {
  param([string]$ProjectFilter)

  $envNames = @("GITHUB_WORKSPACE", "SOLUTION_NAME", "RESHARPER_REPORT_PATH", "RESHARPER_PROJECT_FILTER")
  $savedEnv = @{}
  foreach ($name in $envNames) {
    $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
  }

  function jb { $args }

  try {
    $env:GITHUB_WORKSPACE = Join-Path $repoRoot "workspace with spaces"
    $env:SOLUTION_NAME = "solutions/Test Library.slnx"
    $env:RESHARPER_REPORT_PATH = "CodeQualityResults.xml"
    $env:RESHARPER_PROJECT_FILTER = $ProjectFilter
    & $inspectCodeScript
  } finally {
    foreach ($name in $envNames) {
      [Environment]::SetEnvironmentVariable($name, $savedEnv[$name])
    }
  }
}

Invoke-TestCase -Name "inspects source across the solution and writes the Sonar XML report by default" -ScriptBlock {
  $workspace = Join-Path $repoRoot "workspace with spaces"
  $reportPath = Join-Path $workspace "CodeQualityResults.xml"
  $arguments = @(Get-InspectCodeArguments -ProjectFilter " ")
  Assert-SequenceEqual -Actual $arguments -Expected @(
    "inspectcode"
    (Join-Path $workspace "solutions/Test Library.slnx")
    "-o=$reportPath"
    "--format=Xml"
    "--include=**/*.cs;**/*.fs;**/*.fsi;**/*.vb;**/*.razor;**/*.cshtml;**/*.vbhtml;**/*.xaml;**/*.axaml"
    "--exclude=**/bin/**;**/obj/**;**/.nuget/packages/**"
  ) -Message "InspectCode should receive the solution, report, and source scope as separate arguments."
}

Invoke-TestCase -Name "passes the caller's library project filter as one argument" -ScriptBlock {
  $body = $step.Groups["body"].Value
  Assert-True -Condition $body.Contains('RESHARPER_PROJECT_FILTER: ${{ inputs.resharper_project_filter }}') -Message "The workflow input should be passed to the step."
  $defaultArguments = @(Get-InspectCodeArguments -ProjectFilter "")
  $filteredArguments = @(Get-InspectCodeArguments -ProjectFilter "  My Library*  ")
  Assert-SequenceEqual -Actual $filteredArguments -Expected ($defaultArguments + "--project=My Library*") -Message "The project filter should extend, not replace, the source scope."
}

Assert-TestFrameworkSuccess
