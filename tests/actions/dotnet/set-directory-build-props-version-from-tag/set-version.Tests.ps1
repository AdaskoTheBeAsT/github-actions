Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\..\.."))
$scriptPath = Join-Path $repoRoot ".github/actions/dotnet/set-directory-build-props-version-from-tag/set-version.ps1"
$failures = New-Object System.Collections.Generic.List[string]

function New-TestDirectory {
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $path | Out-Null
  return $path
}

function Invoke-ActionScript {
  param(
    [string]$WorkingDirectory,
    [string]$Tag,
    [string]$StripVPrefix = "true",
    [string]$FailIfNotSemver = "false"
  )

  $outputPath = Join-Path $WorkingDirectory "github_output.txt"

  Push-Location $WorkingDirectory
  try {
    $env:GITHUB_OUTPUT = $outputPath
    & $scriptPath -Tag $Tag -StripVPrefix $StripVPrefix -FailIfNotSemver $FailIfNotSemver
  } finally {
    Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    Pop-Location
  }

  return $outputPath
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

Invoke-TestCase -Name "updates the first Version node and preserves additional ones" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    $propsPath = Join-Path $testDirectory "Directory.Build.props"
    Set-Content -LiteralPath $propsPath -Encoding utf8NoBOM -Value @'
<Project>
  <PropertyGroup>
    <Version>0.0.1</Version>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Configuration)' == 'Release'">
    <Version>9.9.9</Version>
  </PropertyGroup>
</Project>
'@

    $outputPath = Invoke-ActionScript -WorkingDirectory $testDirectory -Tag "v1.2.3" -StripVPrefix "true" -FailIfNotSemver "true"

    $content = Get-Content -Raw -LiteralPath $propsPath
    Assert-True -Condition (-not $content.StartsWith("<?xml")) -Message "The script should not add an XML declaration."

    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($propsPath)
    $versionNodes = $xml.SelectNodes("/Project/PropertyGroup/Version")

    Assert-Equal -Actual $versionNodes.Count -Expected 2 -Message "The script should preserve all Version nodes."
    Assert-Equal -Actual $versionNodes.Item(0).InnerText -Expected "1.2.3" -Message "The first Version node was not updated."
    Assert-Equal -Actual $versionNodes.Item(1).InnerText -Expected "9.9.9" -Message "The additional Version node should remain unchanged."
    Assert-Match -Actual (Get-Content -Raw -LiteralPath $outputPath) -Pattern "version=1\.2\.3" -Message "The GitHub output file was not updated."
  } finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "adds Version when it does not exist" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    $propsPath = Join-Path $testDirectory "Directory.Build.props"
    Set-Content -LiteralPath $propsPath -Encoding utf8NoBOM -Value @'
<Project>
</Project>
'@

    Invoke-ActionScript -WorkingDirectory $testDirectory -Tag "1.2.4" -StripVPrefix "true" -FailIfNotSemver "true" | Out-Null

    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($propsPath)
    $versionNodes = $xml.SelectNodes("/Project/PropertyGroup/Version")

    Assert-Equal -Actual $versionNodes.Count -Expected 1 -Message "The script should add a Version node."
    Assert-Equal -Actual $versionNodes.Item(0).InnerText -Expected "1.2.4" -Message "The added Version node has the wrong value."
  } finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when the root Directory.Build.props file is missing" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    Assert-Throws -ScriptBlock { Invoke-ActionScript -WorkingDirectory $testDirectory -Tag "1.2.5" -StripVPrefix "true" -FailIfNotSemver "true" } -Message "The script should fail when Directory.Build.props is missing."
  } finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

Invoke-TestCase -Name "fails when semver-like validation is required and the tag is invalid" -ScriptBlock {
  $testDirectory = New-TestDirectory

  try {
    $propsPath = Join-Path $testDirectory "Directory.Build.props"
    Set-Content -LiteralPath $propsPath -Encoding utf8NoBOM -Value @'
<Project>
  <PropertyGroup>
    <Version>0.0.1</Version>
  </PropertyGroup>
</Project>
'@

    Assert-Throws -ScriptBlock { Invoke-ActionScript -WorkingDirectory $testDirectory -Tag "release" -StripVPrefix "true" -FailIfNotSemver "true" } -Message "The script should fail when semver-like validation is enabled."
  } finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
  }
}

if ($failures.Count -gt 0) {
  throw ("{0} test(s) failed.`n`n{1}" -f $failures.Count, ($failures -join "`n`n"))
}

Write-Host "All tests passed."
