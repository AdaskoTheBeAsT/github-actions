[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Tag,

  [string]$StripVPrefix = "true",

  [string]$FailIfNotSemver = "false"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-InputIsTrue {
  param(
    [AllowNull()]
    [string]$Value
  )

  return $null -ne $Value -and $Value.Trim().Equals("true", [System.StringComparison]::OrdinalIgnoreCase)
}

if ([string]::IsNullOrWhiteSpace($Tag)) {
  throw "Input 'tag' is empty."
}

$rawTag = $Tag.Trim()
$effectiveTag = $rawTag

if ((Test-InputIsTrue -Value $StripVPrefix) -and $effectiveTag -imatch "^v(?=\d+\.\d+\.\d+)") {
  $effectiveTag = $effectiveTag.Substring(1)
}

$semVerPattern = "^(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z\-\.]+)?(\+[0-9A-Za-z\-\.]+)?$"
if ($effectiveTag -notmatch $semVerPattern) {
  if (Test-InputIsTrue -Value $FailIfNotSemver) {
    throw "Tag '$rawTag' (effective '$effectiveTag') is not semver-like."
  }

  Write-Warning "Tag '$rawTag' (effective '$effectiveTag') is not semver-like. Continuing."
}

$files = Get-ChildItem -Path . -Filter Directory.Build.props -File
if (-not $files) {
  throw "Root Directory.Build.props was not found."
}

foreach ($file in $files) {
  $xml = New-Object System.Xml.XmlDocument
  $xml.PreserveWhitespace = $true
  $xml.Load($file.FullName)

  if (-not $xml.DocumentElement -or $xml.DocumentElement.Name -ne "Project") {
    throw "[$($file.Name)] Root element must be <Project>."
  }

  $projectNode = $xml.DocumentElement
  $propertyGroups = $projectNode.SelectNodes("PropertyGroup")
  if (-not $propertyGroups -or $propertyGroups.Count -eq 0) {
    $firstPropertyGroup = $xml.CreateElement("PropertyGroup")
    $projectNode.AppendChild($firstPropertyGroup) | Out-Null
  } else {
    $firstPropertyGroup = $propertyGroups.Item(0)
  }

  $versionNodes = $projectNode.SelectNodes("PropertyGroup/Version")

  if (-not $versionNodes -or $versionNodes.Count -eq 0) {
    $newVersionNode = $xml.CreateElement("Version")
    $newVersionNode.InnerText = $effectiveTag
    $firstPropertyGroup.AppendChild($newVersionNode) | Out-Null
    Write-Host "[$($file.Name)] Added <Version>$effectiveTag</Version>"
  } else {
    $primaryVersionNode = $versionNodes.Item(0)
    if ($versionNodes.Count -gt 1) {
      Write-Warning "[$($file.Name)] Multiple <Version> elements found. Updating only the first and leaving the rest unchanged."
    }

    $oldVersion = ""
    if ($null -ne $primaryVersionNode.InnerText) {
      $oldVersion = $primaryVersionNode.InnerText.Trim()
    }

    $primaryVersionNode.InnerText = $effectiveTag
    Write-Host "[$($file.Name)] <Version> set: '$oldVersion' -> '$effectiveTag'"
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $settings = New-Object System.Xml.XmlWriterSettings
  $settings.Encoding = $utf8NoBom
  $settings.Indent = $false
  $settings.OmitXmlDeclaration = -not ($xml.FirstChild -is [System.Xml.XmlDeclaration])

  $writer = [System.Xml.XmlWriter]::Create($file.FullName, $settings)
  try {
    $xml.Save($writer)
  } finally {
    $writer.Dispose()
  }
}

Write-Host "Final version written: $effectiveTag"
if ($env:GITHUB_OUTPUT) {
  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "version=$effectiveTag"
}
