[CmdletBinding()]
param(
  [string]$SonarProvider = "sonarcloud",

  [Parameter(Mandatory = $true)]
  [string]$ProjectKey,

  [AllowEmptyString()]
  [string]$SonarOrganization = "",

  [Parameter(Mandatory = $true)]
  [string]$SonarToken,

  [Parameter(Mandatory = $true)]
  [string]$SonarHostUrl,

  [string]$SettingsFile = "SonarQube.Analysis.xml",

  [string]$RunReSharperInspectCode = "false",

  [AllowEmptyString()]
  [string]$ReSharperReportPath = "",

  [Parameter(Mandatory = $true)]
  [string]$EventName,

  [AllowEmptyString()]
  [string]$GitRef = "",

  [AllowEmptyString()]
  [string]$RefName = "",

  [AllowEmptyString()]
  [string]$BranchName = "",

  [AllowEmptyString()]
  [string]$PullRequestKey = "",

  [AllowEmptyString()]
  [string]$PullRequestBranch = "",

  [AllowEmptyString()]
  [string]$PullRequestBase = ""
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

function Get-NormalizedSonarProvider {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "sonarcloud"
  }

  $normalizedValue = $Value.Trim().ToLowerInvariant()
  if ($normalizedValue -notin @("sonarcloud", "sonarqube")) {
    throw "Input 'sonar_provider' must be either 'sonarcloud' or 'sonarqube'."
  }

  return $normalizedValue
}

function Test-InputIsTrue {
  param(
    [AllowNull()]
    [string]$Value
  )

  return $null -ne $Value -and $Value.Trim().Equals("true", [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-TagRef {
  param(
    [AllowNull()]
    [string]$Value
  )

  return -not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim().StartsWith("refs/tags/", [System.StringComparison]::Ordinal)
}

$normalizedSonarProvider = Get-NormalizedSonarProvider -Value $SonarProvider
Assert-NotWhiteSpace -Value $ProjectKey -Name "project_key"
if ($normalizedSonarProvider -eq "sonarcloud") {
  Assert-NotWhiteSpace -Value $SonarOrganization -Name "sonar_organization"
}
Assert-NotWhiteSpace -Value $SonarToken -Name "sonar_token"
Assert-NotWhiteSpace -Value $SonarHostUrl -Name "sonar_host_url"
Assert-NotWhiteSpace -Value $SettingsFile -Name "settings_file"
Assert-NotWhiteSpace -Value $EventName -Name "event_name"

$settingsPath = Resolve-WorkspaceRelativePath -Path $SettingsFile
$beginArguments = @(
  "begin",
  "/k:`"$ProjectKey`"",
  "/d:sonar.token=`"$SonarToken`"",
  "/d:sonar.host.url=`"$SonarHostUrl`"",
  "/s:`"$settingsPath`""
)

if ($normalizedSonarProvider -eq "sonarcloud") {
  $beginArguments += "/o:`"$SonarOrganization`""
}

if (Test-InputIsTrue -Value $RunReSharperInspectCode) {
  Assert-NotWhiteSpace -Value $ReSharperReportPath -Name "resharper_report_path"
  $resharperReportFullPath = Resolve-WorkspaceRelativePath -Path $ReSharperReportPath
  $beginArguments += "/d:sonar.resharper.cs.reportPath=`"$resharperReportFullPath`""
}

if ($EventName.Equals("pull_request", [System.StringComparison]::OrdinalIgnoreCase)) {
  Assert-NotWhiteSpace -Value $PullRequestKey -Name "pull_request_key"
  Assert-NotWhiteSpace -Value $PullRequestBranch -Name "pull_request_branch"
  Assert-NotWhiteSpace -Value $PullRequestBase -Name "pull_request_base"

  $beginArguments += @(
    "/d:sonar.pullrequest.key=`"$PullRequestKey`"",
    "/d:sonar.pullrequest.branch=`"$PullRequestBranch`"",
    "/d:sonar.pullrequest.base=`"$PullRequestBase`""
  )
} elseif (Test-TagRef -Value $GitRef) {
  Assert-NotWhiteSpace -Value $RefName -Name "ref_name"
  $beginArguments += "/d:sonar.projectVersion=`"$RefName`""
} else {
  Assert-NotWhiteSpace -Value $BranchName -Name "branch_name"
  $beginArguments += "/d:sonar.branch.name=`"$BranchName`""
}

Write-Host "Starting $normalizedSonarProvider analysis for event '$EventName'."
& dotnet-sonarscanner @beginArguments
