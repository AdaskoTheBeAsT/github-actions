Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$scriptPath = Join-Path $repoRoot ".github/actions/dotnet/test-with-coverage/test-with-coverage.ps1"

Import-Module -Force (Join-Path $repoRoot "tests/_shared/TestFramework.psm1")
Reset-TestFramework

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
      $global:LASTEXITCODE = 0
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

Invoke-TestCase -Name "runs MTP solution tests through dotnet-coverage" -ScriptBlock {
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
      $global:LASTEXITCODE = 0
    }

    & $scriptPath `
      -SolutionName "src/My Solution.sln" `
      -CoverageSettingsFile "config/coverage.settings.xml" `
      -ResultsDirectory "Test Results" `
      -CoverageOutputFile "artifacts/coverage.xml" `
      -RunnerType "mtp"

    Assert-Equal -Actual $global:CapturedCoverageArguments[0] -Expected "collect" -Message "MTP should be wrapped by dotnet-coverage collect."
    Assert-True -Condition ($global:CapturedCoverageArguments[1] -like 'dotnet test --solution "src/My Solution.sln"*') -Message "MTP should use the --solution option followed by the quoted solution path."
    Assert-True -Condition ($global:CapturedCoverageArguments[1] -like '*--report-trx*') -Message "MTP should request TRX reports."
    Assert-True -Condition ($global:CapturedCoverageArguments[1] -notlike '*--report-gh*') -Message "MTP should not request the GitHub report when its extension is unavailable."
    Assert-True -Condition ($global:CapturedCoverageArguments[1] -notlike '*--logger*') -Message "MTP should not use the VSTest logger option."
    Assert-True -Condition ($global:CapturedCoverageArguments[1] -notlike '*--coverage*') -Message "MTP should let the outer dotnet-coverage process collect coverage."
    Assert-True -Condition ($global:CapturedCoverageArguments -contains "--settings") -Message "The coverage settings should be passed to dotnet-coverage."
    Assert-True -Condition ($global:CapturedCoverageArguments -contains (Join-Path $workingDirectory "config\coverage.settings.xml")) -Message "The coverage settings file should be resolved from the workspace."
    Assert-True -Condition ($global:CapturedCoverageArguments -contains "artifacts/coverage.xml") -Message "dotnet-coverage should use the requested output path."
  } finally {
    Remove-Item Function:\global:dotnet-coverage -ErrorAction SilentlyContinue
    Remove-Variable CapturedCoverageArguments -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "enables the MTP GitHub report when its package is resolved" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:GITHUB_ACTIONS = "true"
    $assetsDirectory = Join-Path $workingDirectory "tests\Example.Tests\obj"
    New-Item -ItemType Directory -Force -Path $assetsDirectory | Out-Null
    @'
{
  "libraries": {
    "Microsoft.Testing.Extensions.GitHubActionsReport/1.0.0": {
      "type": "package"
    }
  }
}
'@ | Set-Content -LiteralPath (Join-Path $assetsDirectory "project.assets.json")
    $global:CapturedCoverageArguments = @()

    function global:dotnet-coverage {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedCoverageArguments = @($Arguments)
      $global:LASTEXITCODE = 0
    }

    & $scriptPath -SolutionName "Example.sln" -RunnerType "mtp"

    Assert-True -Condition ($global:CapturedCoverageArguments[1] -like '*--report-gh*') -Message "MTP should enable the GitHub report when the package is resolved."
  } finally {
    Remove-Item Function:\global:dotnet-coverage -ErrorAction SilentlyContinue
    Remove-Variable CapturedCoverageArguments -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_ACTIONS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when the runner type is unsupported" -ScriptBlock {
  Assert-Throws -ScriptBlock {
    & $scriptPath -SolutionName "My.sln" -RunnerType "other"
  } -Message "The script should fail when runner_type is unsupported."
}

Invoke-TestCase -Name "exports env_vars and env_secrets entries to the test process" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:TEST_ENV_VARS = "MYAPP_TEST_MODE=ci`n`n# a comment`nMYAPP_EMPTY="
    $env:TEST_ENV_SECRETS = "  MYAPP_LICENSE_KEY = super secret = value  "
    $global:CapturedTestEnvironment = @{}

    function global:dotnet-coverage {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      foreach ($name in @("MYAPP_TEST_MODE", "MYAPP_EMPTY", "MYAPP_LICENSE_KEY", "TEST_ENV_VARS", "TEST_ENV_SECRETS")) {
        $global:CapturedTestEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name)
      }

      $global:LASTEXITCODE = 0
    }

    $hostOutput = @(& $scriptPath -SolutionName "My.sln" 6>&1 | ForEach-Object { [string]$_ })

    Assert-Equal -Actual $global:CapturedTestEnvironment["MYAPP_TEST_MODE"] -Expected "ci" -Message "A non-secret pair should be exported."
    Assert-Equal -Actual $global:CapturedTestEnvironment["MYAPP_EMPTY"] -Expected "" -Message "An entry without a value should be exported as an empty string."
    Assert-Equal -Actual $global:CapturedTestEnvironment["MYAPP_LICENSE_KEY"] -Expected "super secret = value" -Message "Only the first '=' should separate name and value."
    Assert-Equal -Actual $global:CapturedTestEnvironment["TEST_ENV_VARS"] -Expected $null -Message "The raw env_vars payload should not reach the test process."
    Assert-Equal -Actual $global:CapturedTestEnvironment["TEST_ENV_SECRETS"] -Expected $null -Message "The raw env_secrets payload should not reach the test process."
    Assert-True -Condition ($hostOutput -contains "::add-mask::super secret = value") -Message "Every secret value should be masked."
    Assert-True -Condition (@($hostOutput -like "::add-mask::*").Count -eq 1) -Message "Only secret values should be masked."
  } finally {
    Remove-Item Function:\global:dotnet-coverage -ErrorAction SilentlyContinue
    Remove-Variable CapturedTestEnvironment -Scope Global -ErrorAction SilentlyContinue
    foreach ($name in @("GITHUB_WORKSPACE", "TEST_ENV_VARS", "TEST_ENV_SECRETS", "MYAPP_TEST_MODE", "MYAPP_EMPTY", "MYAPP_LICENSE_KEY")) {
      Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when an env entry is not in NAME=VALUE format" -ScriptBlock {
  try {
    $env:TEST_ENV_VARS = "MYAPP_TEST_MODE"

    Assert-Throws -ScriptBlock {
      & $scriptPath -SolutionName "My.sln"
    } -Message "The script should fail when an env entry has no '=' separator."
  } finally {
    Remove-Item Env:TEST_ENV_VARS -ErrorAction SilentlyContinue
  }
}

Invoke-TestCase -Name "fails when an env entry uses an invalid variable name" -ScriptBlock {
  try {
    $env:TEST_ENV_SECRETS = "MY-APP LICENSE=abc"

    Assert-Throws -ScriptBlock {
      & $scriptPath -SolutionName "My.sln"
    } -Message "The script should fail when an env entry name is not a valid environment variable name."
  } finally {
    Remove-Item Env:TEST_ENV_SECRETS -ErrorAction SilentlyContinue
  }
}

Assert-TestFrameworkSuccess
