Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$scriptPath = Join-Path $repoRoot ".github/actions/dotnet/publish-nuget-packages/publish-nuget-packages.ps1"
$validateScriptPath = Join-Path $repoRoot ".github/actions/dotnet/publish-nuget-packages/validate-publish-inputs.ps1"
$actionManifestPath = Join-Path $repoRoot ".github/actions/dotnet/publish-nuget-packages/action.yml"
$workflowPath = Join-Path $repoRoot ".github/workflows/dotnet-build-sonarqube-nuget.yml"

Import-Module -Force (Join-Path $repoRoot "tests/_shared/TestFramework.psm1")
Reset-TestFramework

Invoke-TestCase -Name "publishes only regular NuGet packages" -ScriptBlock {
  $workingDirectory = New-TestDirectory
  $outputDirectory = Join-Path $workingDirectory "artifacts\nuget"

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:NUGET_API_KEY = "api-key"
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
      -NugetSourceUrl "https://api.nuget.org/v3/index.json"

    Assert-Equal -Actual $global:CapturedDotnetCalls.Count -Expected 1 -Message "Only publishable packages should be pushed."
    Assert-True -Condition ($global:CapturedDotnetCalls[0] -contains "nuget") -Message "The dotnet nuget command was not used."
    Assert-True -Condition ($global:CapturedDotnetCalls[0] -contains "push") -Message "The dotnet nuget push command was not used."
    Assert-True -Condition ($global:CapturedDotnetCalls[0] -contains (Join-Path $outputDirectory "Library.1.0.0.nupkg")) -Message "The regular package should be pushed."
    Assert-True -Condition (-not ($global:CapturedDotnetCalls[0] -contains (Join-Path $outputDirectory "Library.1.0.0.snupkg"))) -Message "The symbols package should not be pushed."
  } finally {
    Remove-Item Function:\global:dotnet -ErrorAction SilentlyContinue
    Remove-Variable CapturedDotnetCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:NUGET_API_KEY -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "publishes multiple regular NuGet packages from one repository" -ScriptBlock {
  $workingDirectory = New-TestDirectory
  $outputDirectory = Join-Path $workingDirectory "artifacts\nuget"

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:NUGET_API_KEY = "api-key"
    $global:CapturedDotnetCalls = New-Object System.Collections.Generic.List[string[]]
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.Abstractions.1.0.0.nupkg") | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.Abstractions.1.0.0.snupkg") | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.Core.1.0.0.nupkg") | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.Core.1.0.0.snupkg") | Out-Null

    function global:dotnet {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:CapturedDotnetCalls.Add(@($Arguments)) | Out-Null
    }

    & $scriptPath `
      -PackageOutputDirectory "artifacts/nuget" `
      -NugetSourceUrl "https://api.nuget.org/v3/index.json"

    Assert-Equal -Actual $global:CapturedDotnetCalls.Count -Expected 2 -Message "Both regular packages should be pushed."
    $pushedFiles = @($global:CapturedDotnetCalls | ForEach-Object { $_[2] })
    Assert-True -Condition ($pushedFiles -contains (Join-Path $outputDirectory "Library.Abstractions.1.0.0.nupkg")) -Message "Library.Abstractions package should be pushed."
    Assert-True -Condition ($pushedFiles -contains (Join-Path $outputDirectory "Library.Core.1.0.0.nupkg")) -Message "Library.Core package should be pushed."
  } finally {
    Remove-Item Function:\global:dotnet -ErrorAction SilentlyContinue
    Remove-Variable CapturedDotnetCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:NUGET_API_KEY -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when no publishable packages are found" -ScriptBlock {
  $workingDirectory = New-TestDirectory

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:NUGET_API_KEY = "api-key"
    New-Item -ItemType Directory -Path (Join-Path $workingDirectory "artifacts\nuget") | Out-Null

    Assert-Throws -ScriptBlock {
      & $scriptPath `
        -PackageOutputDirectory "artifacts/nuget" `
        -NugetSourceUrl "https://api.nuget.org/v3/index.json"
    } -Message "The script should fail when no publishable packages are present."
  } finally {
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:NUGET_API_KEY -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when NUGET_API_KEY environment variable is missing" -ScriptBlock {
  $workingDirectory = New-TestDirectory
  $outputDirectory = Join-Path $workingDirectory "artifacts\nuget"

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    Remove-Item Env:NUGET_API_KEY -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.1.0.0.nupkg") | Out-Null

    Assert-Throws -ScriptBlock {
      & $scriptPath `
        -PackageOutputDirectory "artifacts/nuget" `
        -NugetSourceUrl "https://api.nuget.org/v3/index.json"
    } -Message "The script should fail when NUGET_API_KEY is not set."
  } finally {
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when dotnet nuget push returns a non-zero exit code" -ScriptBlock {
  $workingDirectory = New-TestDirectory
  $outputDirectory = Join-Path $workingDirectory "artifacts\nuget"

  try {
    $env:GITHUB_WORKSPACE = $workingDirectory
    $env:NUGET_API_KEY = "api-key"
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    New-Item -ItemType File -Path (Join-Path $outputDirectory "Library.1.0.0.nupkg") | Out-Null

    function global:dotnet {
      param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
      )

      $global:LASTEXITCODE = 1
    }

    Assert-Throws -ScriptBlock {
      & $scriptPath `
        -PackageOutputDirectory "artifacts/nuget" `
        -NugetSourceUrl "https://api.nuget.org/v3/index.json"
    } -Message "The script should fail when dotnet nuget push returns a non-zero exit code."
  } finally {
    $global:LASTEXITCODE = 0
    Remove-Item Function:\global:dotnet -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_WORKSPACE -ErrorAction SilentlyContinue
    Remove-Item Env:NUGET_API_KEY -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "validates OIDC trusted publishing inputs and artifact download flag" -ScriptBlock {
  $workingDirectory = New-TestDirectory
  $outputFile = Join-Path $workingDirectory "github_output.txt"

  try {
    New-Item -ItemType File -Path $outputFile | Out-Null
    $env:GITHUB_OUTPUT = $outputFile
    Remove-Item Env:INPUT_NUGET_API_KEY -ErrorAction SilentlyContinue

    & $validateScriptPath `
      -PackageOutputDirectory "artifacts/nuget" `
      -ArtifactName " nuget-packages " `
      -NugetSourceUrl "https://api.nuget.org/v3/index.json" `
      -NugetUser " adasko "

    $outputs = Get-Content -LiteralPath $outputFile
    Assert-True -Condition ($outputs -contains "download_artifact=true") -Message "Expected download_artifact=true when artifact_name is provided."
    Assert-True -Condition ($outputs -contains "artifact_name=nuget-packages") -Message "Expected trimmed artifact_name output."
    Assert-True -Condition ($outputs -contains "use_trusted_publishing=true") -Message "Expected use_trusted_publishing=true when nuget_user is provided."
    Assert-True -Condition ($outputs -contains "nuget_user=adasko") -Message "Expected trimmed nuget_user output."
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "validates explicit API key mode without artifact download" -ScriptBlock {
  $workingDirectory = New-TestDirectory
  $outputFile = Join-Path $workingDirectory "github_output.txt"

  try {
    New-Item -ItemType File -Path $outputFile | Out-Null
    $env:GITHUB_OUTPUT = $outputFile
    $env:INPUT_NUGET_API_KEY = "explicit-key"

    & $validateScriptPath `
      -PackageOutputDirectory "artifacts/nuget" `
      -ArtifactName "   " `
      -NugetSourceUrl "https://api.nuget.org/v3/index.json" `
      -NugetUser ""

    $outputs = Get-Content -LiteralPath $outputFile
    Assert-True -Condition ($outputs -contains "download_artifact=false") -Message "Expected download_artifact=false when artifact_name is blank."
    Assert-True -Condition ($outputs -contains "use_trusted_publishing=false") -Message "Expected use_trusted_publishing=false when nuget_api_key is used."
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:INPUT_NUGET_API_KEY -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "rejects missing or conflicting authentication inputs" -ScriptBlock {
  Remove-Item Env:INPUT_NUGET_API_KEY -ErrorAction SilentlyContinue

  Assert-Throws -ScriptBlock {
    & $validateScriptPath `
      -PackageOutputDirectory "artifacts/nuget" `
      -ArtifactName "" `
      -NugetSourceUrl "https://api.nuget.org/v3/index.json" `
      -NugetUser ""
  } -Message "Validation should fail when neither nuget_user nor nuget_api_key is provided."

  try {
    $env:INPUT_NUGET_API_KEY = "explicit-key"
    Assert-Throws -ScriptBlock {
      & $validateScriptPath `
        -PackageOutputDirectory "artifacts/nuget" `
        -ArtifactName "" `
        -NugetSourceUrl "https://api.nuget.org/v3/index.json" `
        -NugetUser "adasko"
    } -Message "Validation should fail when both nuget_user and nuget_api_key are provided."
  } finally {
    Remove-Item Env:INPUT_NUGET_API_KEY -ErrorAction SilentlyContinue
  }
}

Invoke-TestCase -Name "reusable workflow uploads package artifact instead of running NuGet/login directly" -ScriptBlock {
  $workflowContent = Get-Content -LiteralPath $workflowPath -Raw
  $actionContent = Get-Content -LiteralPath $actionManifestPath -Raw

  Assert-True -Condition (-not ($workflowContent -match '(?m)^\s+uses:\s*NuGet/login')) -Message "Reusable workflow must not invoke NuGet/login directly because cross-repository job_workflow_ref fails NuGet Trusted Publishing."
  Assert-True -Condition (-not ($workflowContent -match '(?m)^\s+id-token:\s*write')) -Message "Reusable workflow should not require id-token: write permission."
  Assert-True -Condition ($workflowContent -match '(?m)^\s+nuget_artifact_name:') -Message "Reusable workflow should expose nuget_artifact_name input and output."
  Assert-True -Condition ($actionContent -match 'uses:\s*NuGet/login@') -Message "Composite publish-nuget-packages action should invoke NuGet/login so OIDC runs under the caller job_workflow_ref."
  Assert-True -Condition ($actionContent -match 'uses:\s*actions/download-artifact@') -Message "Composite publish-nuget-packages action should support downloading the packed NuGet artifact."
}

Assert-TestFrameworkSuccess
