Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$scriptPath = Join-Path $repoRoot ".github/actions/dotnet/setup-dotnet-sdks/resolve-dotnet-sdk-versions.ps1"

Import-Module -Force (Join-Path $repoRoot "tests/_shared/TestFramework.psm1")
Reset-TestFramework

function Get-GitHubOutputValue {
  param(
    [string]$Path,
    [string]$Name
  )

  $lines = Get-Content -LiteralPath $Path
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith("$Name<<", [System.StringComparison]::Ordinal)) {
      $delimiter = $lines[$i].Substring($Name.Length + 2)
      $values = New-Object System.Collections.Generic.List[string]
      for ($j = $i + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j] -eq $delimiter) {
          return ,@($values.ToArray())
        }

        $values.Add($lines[$j]) | Out-Null
      }

      throw "Output '$Name' did not end with delimiter '$delimiter'."
    }

    if ($lines[$i].StartsWith("$Name=", [System.StringComparison]::Ordinal)) {
      return ,@($lines[$i].Substring($Name.Length + 1))
    }
  }

  throw "Output '$Name' was not found."
}

Invoke-TestCase -Name "uses dotnet_versions when provided and trims entries" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    $outputPath = Join-Path $testDirectory "github_output.txt"
    $env:GITHUB_OUTPUT = $outputPath

    & $scriptPath -DotnetVersions "8.0.x, 9.0.x , ,6.0.x"

    $versions = Get-GitHubOutputValue -Path $outputPath -Name "versions"
    $globalJsonFile = Get-GitHubOutputValue -Path $outputPath -Name "global_json_file"
    Assert-SequenceEqual -Actual $versions -Expected @("8.0.x", "9.0.x", "6.0.x") -Message "The resolved SDK versions were incorrect."
    Assert-SequenceEqual -Actual $globalJsonFile -Expected @("") -Message "global_json_file should be empty when use_global_json is false."
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "accepts a single SDK version in dotnet_versions" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    $outputPath = Join-Path $testDirectory "github_output.txt"
    $env:GITHUB_OUTPUT = $outputPath

    & $scriptPath -DotnetVersions "9.0.x"

    $versions = Get-GitHubOutputValue -Path $outputPath -Name "versions"
    Assert-SequenceEqual -Actual $versions -Expected @("9.0.x") -Message "A single SDK version should be accepted in dotnet_versions."
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when no SDK version input is provided" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    $outputPath = Join-Path $testDirectory "github_output.txt"
    $env:GITHUB_OUTPUT = $outputPath

    Assert-Throws -ScriptBlock { & $scriptPath -DotnetVersions " " } -Message "The script should fail when dotnet_versions is empty and use_global_json is false."
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "supports global.json without explicit dotnet_versions" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    $outputPath = Join-Path $testDirectory "github_output.txt"
    $env:GITHUB_OUTPUT = $outputPath

    & $scriptPath -DotnetVersions " " -UseGlobalJson "true"

    $versions = Get-GitHubOutputValue -Path $outputPath -Name "versions"
    $globalJsonFile = Get-GitHubOutputValue -Path $outputPath -Name "global_json_file"
    Assert-SequenceEqual -Actual $versions -Expected @("") -Message "versions should be empty when only global.json is used."
    Assert-SequenceEqual -Actual $globalJsonFile -Expected @("global.json") -Message "global_json_file should point to the root global.json when the flag is enabled."
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "supports dotnet_versions together with global.json" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    $outputPath = Join-Path $testDirectory "github_output.txt"
    $env:GITHUB_OUTPUT = $outputPath

    & $scriptPath -DotnetVersions "8.0.x, 9.0.x" -UseGlobalJson "true"

    $versions = Get-GitHubOutputValue -Path $outputPath -Name "versions"
    $globalJsonFile = Get-GitHubOutputValue -Path $outputPath -Name "global_json_file"
    Assert-SequenceEqual -Actual $versions -Expected @("8.0.x", "9.0.x") -Message "The explicit SDK versions should still be preserved when global.json is enabled."
    Assert-SequenceEqual -Actual $globalJsonFile -Expected @("global.json") -Message "global_json_file should point to the root global.json when the flag is enabled."
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when GITHUB_OUTPUT is not available" -ScriptBlock {
  Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
  Assert-Throws -ScriptBlock { & $scriptPath -DotnetVersions "9.0.x" } -Message "The script should fail when GITHUB_OUTPUT is missing."
}

Assert-TestFrameworkSuccess
