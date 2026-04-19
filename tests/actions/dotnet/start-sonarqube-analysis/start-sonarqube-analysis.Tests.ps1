Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$scriptPath = Join-Path $repoRoot ".github/actions/dotnet/start-sonarqube-analysis/start-sonarqube-analysis.ps1"

Import-Module -Force (Join-Path $repoRoot "tests/_shared/TestFramework.psm1")
Reset-TestFramework

Invoke-TestCase -Name "starts pull request analysis with pull request arguments" -ScriptBlock {
  $workingDirectory = New-TestDirectory
  $expectedSettingsPath = Join-Path $workingDirectory "config\SonarQube.Analysis.xml"
  $expectedReportPath = Join-Path $workingDirectory "reports\CodeQualityResults.xml"

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:SONAR_TOKEN = "token-value"
    $global:CapturedSonarScannerArguments = @()

    function global:dotnet-sonarscanner {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedSonarScannerArguments = @($Arguments)
    }

    & $scriptPath `
      -SonarProvider "sonarcloud" `
      -ProjectKey "demo-project" `
      -SonarOrganization "demo-org" `
      -SonarHostUrl "https://sonar.example.com" `
      -SettingsFile "config/SonarQube.Analysis.xml" `
      -RunReSharperInspectCode "true" `
      -ReSharperReportPath "reports/CodeQualityResults.xml" `
      -EventName "pull_request" `
      -PullRequestKey "42" `
      -PullRequestBranch "feature/my-change" `
      -PullRequestBase "main"

    Assert-Equal -Actual $global:CapturedSonarScannerArguments[0] -Expected "begin" -Message "The SonarScanner command should start with begin."
    Assert-True -Condition ($global:CapturedSonarScannerArguments -contains '/o:demo-org') -Message "The SonarCloud organization argument was not passed."
    Assert-True -Condition ($global:CapturedSonarScannerArguments -contains '/d:sonar.pullrequest.key=42') -Message "The pull request key argument was not passed."
    Assert-True -Condition ($global:CapturedSonarScannerArguments -contains '/d:sonar.pullrequest.branch=feature/my-change') -Message "The pull request branch argument was not passed."
    Assert-True -Condition ($global:CapturedSonarScannerArguments -contains '/d:sonar.pullrequest.base=main') -Message "The pull request base argument was not passed."
    Assert-True -Condition ($global:CapturedSonarScannerArguments -contains "/s:$expectedSettingsPath") -Message "The settings file path should be resolved from the workspace."
    Assert-True -Condition ($global:CapturedSonarScannerArguments -contains "/d:sonar.resharper.cs.reportPath=$expectedReportPath") -Message "The ReSharper report path should be resolved from the workspace."
    Assert-True -Condition (-not ($global:CapturedSonarScannerArguments -match '^/d:sonar\.token=')) -Message "The Sonar token should not be passed as a CLI argument."
  } finally {
    Remove-Item Function:\global:dotnet-sonarscanner -ErrorAction SilentlyContinue
    Remove-Variable CapturedSonarScannerArguments -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "starts branch analysis with branch argument" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:SONAR_TOKEN = "token-value"
    $global:CapturedSonarScannerArguments = @()

    function global:dotnet-sonarscanner {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedSonarScannerArguments = @($Arguments)
    }

    & $scriptPath `
      -SonarProvider "sonarqube" `
      -ProjectKey "demo-project" `
      -SonarHostUrl "https://sonar.example.com" `
      -SettingsFile "SonarQube.Analysis.xml" `
      -RunReSharperInspectCode "true" `
      -ReSharperReportPath "CodeQualityResults.xml" `
      -EventName "push" `
      -BranchName "main"

    Assert-True -Condition ($global:CapturedSonarScannerArguments -contains '/d:sonar.branch.name=main') -Message "The branch analysis argument was not passed."
    Assert-True -Condition (-not ($global:CapturedSonarScannerArguments -match '^/o:')) -Message "The SonarCloud organization argument should not be present for SonarQube."
    Assert-True -Condition (-not ($global:CapturedSonarScannerArguments -match "pullrequest")) -Message "Pull request arguments should not be present for branch analysis."
  } finally {
    Remove-Item Function:\global:dotnet-sonarscanner -ErrorAction SilentlyContinue
    Remove-Variable CapturedSonarScannerArguments -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "uses the provided scanner path" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:SONAR_TOKEN = "token-value"
    $global:CapturedScannerPath = ""
    $global:CapturedSonarScannerArguments = @()

    function global:custom-sonarscanner {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedScannerPath = "custom-sonarscanner"
      $global:CapturedSonarScannerArguments = @($Arguments)
    }

    & $scriptPath `
      -SonarProvider "sonarqube" `
      -ProjectKey "demo-project" `
      -SonarHostUrl "https://sonar.example.com" `
      -SettingsFile "SonarQube.Analysis.xml" `
      -ScannerPath "custom-sonarscanner" `
      -RunReSharperInspectCode "false" `
      -EventName "push" `
      -BranchName "main"

    Assert-Equal -Actual $global:CapturedScannerPath -Expected "custom-sonarscanner" -Message "The configured scanner path should be used."
    Assert-Equal -Actual $global:CapturedSonarScannerArguments[0] -Expected "begin" -Message "The configured scanner should receive the begin command."
  } finally {
    Remove-Item Function:\global:custom-sonarscanner -ErrorAction SilentlyContinue
    Remove-Variable CapturedScannerPath -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable CapturedSonarScannerArguments -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "starts tag analysis with project version argument" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:SONAR_TOKEN = "token-value"
    $global:CapturedSonarScannerArguments = @()

    function global:dotnet-sonarscanner {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedSonarScannerArguments = @($Arguments)
    }

    & $scriptPath `
      -SonarProvider "sonarqube" `
      -ProjectKey "demo-project" `
      -SonarHostUrl "https://sonar.example.com" `
      -SettingsFile "SonarQube.Analysis.xml" `
      -RunReSharperInspectCode "false" `
      -EventName "push" `
      -GitRef "refs/tags/v1.2.3" `
      -RefName "v1.2.3"

    Assert-True -Condition ($global:CapturedSonarScannerArguments -contains '/v:v1.2.3') -Message "The tag analysis argument was not passed."
    Assert-True -Condition (-not ($global:CapturedSonarScannerArguments -match "branch.name")) -Message "Branch analysis argument should not be present for tag analysis."
    Assert-True -Condition (-not ($global:CapturedSonarScannerArguments -match "pullrequest")) -Message "Pull request arguments should not be present for tag analysis."
  } finally {
    Remove-Item Function:\global:dotnet-sonarscanner -ErrorAction SilentlyContinue
    Remove-Variable CapturedSonarScannerArguments -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "skips the ReSharper report argument when the flag is false" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:SONAR_TOKEN = "token-value"
    $global:CapturedSonarScannerArguments = @()

    function global:dotnet-sonarscanner {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedSonarScannerArguments = @($Arguments)
    }

    & $scriptPath `
      -SonarProvider "sonarqube" `
      -ProjectKey "demo-project" `
      -SonarHostUrl "https://sonar.example.com" `
      -SettingsFile "SonarQube.Analysis.xml" `
      -RunReSharperInspectCode "false" `
      -ReSharperReportPath "CodeQualityResults.xml" `
      -EventName "push" `
      -BranchName "main"

    Assert-True -Condition (-not ($global:CapturedSonarScannerArguments -match "resharper")) -Message "The ReSharper report argument should be omitted when the path is empty."
  } finally {
    Remove-Item Function:\global:dotnet-sonarscanner -ErrorAction SilentlyContinue
    Remove-Variable CapturedSonarScannerArguments -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when ReSharper integration is enabled without a report path" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:SONAR_TOKEN = "token-value"
    Assert-Throws -ScriptBlock {
      & $scriptPath `
        -SonarProvider "sonarqube" `
        -ProjectKey "demo-project" `
        -SonarHostUrl "https://sonar.example.com" `
        -SettingsFile "SonarQube.Analysis.xml" `
        -RunReSharperInspectCode "true" `
        -ReSharperReportPath "" `
        -EventName "push" `
        -BranchName "main"
    } -Message "The script should fail when ReSharper integration is enabled without a report path."
  } finally {
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when SonarCloud organization is missing" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:SONAR_TOKEN = "token-value"
    Assert-Throws -ScriptBlock {
      & $scriptPath `
        -SonarProvider "sonarcloud" `
        -ProjectKey "demo-project" `
        -SonarOrganization "" `
        -SonarHostUrl "https://sonarcloud.io" `
        -SettingsFile "SonarQube.Analysis.xml" `
        -EventName "push" `
        -BranchName "main"
    } -Message "The script should fail when SonarCloud organization is missing."
  } finally {
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when SONAR_TOKEN environment variable is missing" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Assert-Throws -ScriptBlock {
      & $scriptPath `
        -SonarProvider "sonarqube" `
        -ProjectKey "demo-project" `
        -SonarHostUrl "https://sonar.example.com" `
        -SettingsFile "SonarQube.Analysis.xml" `
        -EventName "push" `
        -BranchName "main"
    } -Message "The script should fail when SONAR_TOKEN is not set."
  } finally {
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when pull request metadata is missing" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:SONAR_TOKEN = "token-value"
    Assert-Throws -ScriptBlock {
      & $scriptPath `
        -SonarProvider "sonarcloud" `
        -ProjectKey "demo-project" `
        -SonarOrganization "demo-org" `
        -SonarHostUrl "https://sonar.example.com" `
        -SettingsFile "SonarQube.Analysis.xml" `
        -RunReSharperInspectCode "true" `
        -ReSharperReportPath "CodeQualityResults.xml" `
        -EventName "pull_request" `
        -PullRequestKey "42"
    } -Message "The script should fail when pull request metadata is incomplete."
  } finally {
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:SONAR_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Assert-TestFrameworkSuccess
