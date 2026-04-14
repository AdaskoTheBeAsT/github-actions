[CmdletBinding()]
param(
  [string]$PackageOutputDirectory = "artifacts/nuget",

  [Parameter(Mandatory = $true)]
  [string]$NugetSourceUrl,

  [Parameter(Mandatory = $true)]
  [string]$NugetApiKey
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

Assert-NotWhiteSpace -Value $PackageOutputDirectory -Name "package_output_directory"
Assert-NotWhiteSpace -Value $NugetSourceUrl -Name "nuget_source_url"
Assert-NotWhiteSpace -Value $NugetApiKey -Name "nuget_api_key"

$resolvedOutputDirectory = Resolve-WorkspaceRelativePath -Path $PackageOutputDirectory
$packages = @(Get-ChildItem -Path $resolvedOutputDirectory -Filter "*.nupkg" -File | Where-Object {
  $_.Name -notlike "*.snupkg" -and $_.Name -notlike "*.symbols.nupkg"
})

if ($packages.Count -eq 0) {
  throw "No NuGet packages found in '$resolvedOutputDirectory'."
}

foreach ($package in $packages) {
  Write-Host "Publishing $($package.Name) to $NugetSourceUrl"
  & dotnet nuget push $package.FullName `
    --source $NugetSourceUrl `
    --api-key $NugetApiKey `
    --skip-duplicate
}

Write-Host "Publishing completed. Published $($packages.Count) package(s)."
