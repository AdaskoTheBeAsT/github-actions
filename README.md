# AdaskoTheBeAsT github-actions

Reusable GitHub Actions for developers who want clean CI, repeatable releases, and less YAML pain.

## Why this repo exists

These workflows and composite actions help you ship .NET libraries with:
- `dotnet restore`, build, and test
- coverage collection
- SonarCloud or SonarQube analysis
- automatic versioning from git tags
- NuGet packaging and publishing

In short: less copy-paste, more shipping.

## Workflows

### 🚀 `.github/workflows/dotnet-build-sonarqube-nuget.yml`
Reusable workflow for .NET library CI/CD.

This workflow performs its own `actions/checkout`, so the calling workflow does not need a separate checkout step for the job that uses it.

#### What it does
- 📦 checks out the repository with full git history
- 🏷️ detects whether the current ref is a lightweight tag
- 🧰 installs one or more .NET SDKs
- 🔢 optionally updates `Directory.Build.props` version from the tag
- 🏗️ restores and builds the solution
- ✅ runs tests with coverage and publishes TRX test results
- 📊 generates a coverage HTML artifact and workflow summary
- 🔍 runs SonarCloud or SonarQube analysis
- 📤 packs and publishes NuGet packages for lightweight tags

#### How it behaves
- `pull_request` → build, test, coverage, ReSharper inspect, Sonar pull request analysis
- branch build → build, test, coverage, ReSharper inspect, Sonar branch analysis
- tag build → build, test, coverage, Sonar versioned analysis using `sonar.projectVersion`
- lightweight tag → build, test, pack, publish NuGet packages
- annotated tag → skips the package publish path

#### Inputs
- `solution_name` (required): solution to restore, build, test, and pack
- `runs_on`: GitHub Actions runner label, for example `ubuntu-latest` or `windows-latest`
- `sonar_provider`: `sonarcloud` or `sonarqube`, defaults to `sonarcloud`
- `sonar_project_key` (required): Sonar project key
- `sonar_organization`: SonarCloud organization, required when `sonar_provider` is `sonarcloud`
- `dotnet_versions`: comma-separated SDK versions
- `use_global_json`: also install SDK from root `global.json`
- `show_dotnet_info`: run `dotnet --info`
- `run_resharper_inspectcode`: install and run ReSharper InspectCode and include its report in Sonar analysis
- `publish_test_results`: publish TRX results to GitHub checks
- `publish_coverage_report`: generate and publish coverage HTML and workflow summary
- `sonar_host_url`: Sonar server URL, defaults to `https://sonarcloud.io`
- `sonar_settings_file`: path to `SonarQube.Analysis.xml`
- `coverage_settings_file`: path to `coverage.settings.xml`
- `package_output_directory`: pack output directory
- `nuget_source_url`: package feed URL
- `strip_v_prefix`: strips `v`/`V` from tags like `v1.2.3`

#### Required workflow secrets
- `sonar_token`: required for pull request and branch builds
- `nuget_api_key`: required when publishing packages from a lightweight tag

#### Which values must be defined
You do not need to define every repository variable. Some inputs already have defaults in the reusable workflow.

##### Usually define these variables
- `SOLUTION_NAME`
- `SONAR_PROJECT_KEY`
- `SONAR_ORGANIZATION` when using `SONAR_PROVIDER=sonarcloud`
- `DOTNET_VERSIONS` if you want explicit SDK installation instead of relying only on `global.json`

##### Optional variables with built-in defaults
- `RUNS_ON` → defaults to `ubuntu-latest`
- `SONAR_PROVIDER` → defaults to `sonarcloud`
- `USE_GLOBAL_JSON` → defaults to `false`
- `SHOW_DOTNET_INFO` → defaults to `true`
- `RUN_RESHARPER_INSPECTCODE` → defaults to `true`
- `PUBLISH_TEST_RESULTS` → defaults to `true`
- `PUBLISH_COVERAGE_REPORT` → defaults to `true`
- `SONAR_HOST_URL` → defaults to `https://sonarcloud.io`
- `SONAR_SETTINGS_FILE` → defaults to `SonarQube.Analysis.xml`
- `COVERAGE_SETTINGS_FILE` → defaults to `coverage.settings.xml`
- `PACKAGE_OUTPUT_DIRECTORY` → defaults to `artifacts/nuget`
- `NUGET_SOURCE_URL` → defaults to `https://api.nuget.org/v3/index.json`
- `STRIP_V_PREFIX` → defaults to `true`

#### Example usage
```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]
    tags:
      - "v*"

permissions:
  checks: write
  contents: read
  pull-requests: read

jobs:
  build:
    uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@main
    with:
      solution_name: ${{ vars.SOLUTION_NAME }}
      runs_on: ${{ vars.RUNS_ON }}
      sonar_provider: ${{ vars.SONAR_PROVIDER }}
      sonar_project_key: ${{ vars.SONAR_PROJECT_KEY }}
      sonar_organization: ${{ vars.SONAR_ORGANIZATION }}
      dotnet_versions: ${{ vars.DOTNET_VERSIONS }}
      use_global_json: true
    secrets:
      sonar_token: ${{ secrets.SONAR_TOKEN }}
      nuget_api_key: ${{ secrets.NUGET_API_KEY }}
```

#### How to reference the reusable workflow
- use `uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@<ref>`
- replace `<ref>` with a branch, tag, or commit SHA such as `main`, `v1.0.0`, or a pinned SHA
- pass non-sensitive values in `with:`
- pass tokens and credentials in `secrets:`
- do not add a separate checkout step in the calling job unless you have another job outside this reusable workflow that needs it
- keep `checks: write` permission if you want published TRX test results to appear in GitHub checks

#### Minimal reference example
```yaml
jobs:
  ci:
    uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@main
    with:
      solution_name: ${{ vars.SOLUTION_NAME }}
      runs_on: ${{ vars.RUNS_ON }}
      sonar_provider: ${{ vars.SONAR_PROVIDER }}
      sonar_project_key: ${{ vars.SONAR_PROJECT_KEY }}
      sonar_organization: ${{ vars.SONAR_ORGANIZATION }}
      dotnet_versions: ${{ vars.DOTNET_VERSIONS }}
      use_global_json: true
    secrets:
      sonar_token: ${{ secrets.SONAR_TOKEN }}
      nuget_api_key: ${{ secrets.NUGET_API_KEY }}
```

#### Test and coverage reporting
- TRX test results are published to GitHub checks
- coverage HTML is uploaded as the `coverage-report` workflow artifact
- a Markdown coverage summary is appended to the workflow summary
- `ReportGenerator` is used to create the HTML report and summary

## Composite actions

### 🏷️ `.github/actions/dotnet/detect-lightweight-tag`
Detects whether a ref points to a lightweight git tag and exposes `is_lightweight_tag`.

### 🧰 `.github/actions/dotnet/setup-dotnet-sdks`
Installs one or more .NET SDK versions. Supports explicit SDK versions and/or the root `global.json`.

### 🔢 `.github/actions/dotnet/set-directory-build-props-version-from-tag`
Writes the tag version into the root `Directory.Build.props` `<Version>` element and returns the resolved version.

## Secrets and variables setup

The reusable workflow itself receives values through `with:` inputs and `secrets:` mappings from the calling repository.

### 🔐 Organization secrets
Use organization secrets for sensitive values shared across multiple repositories:
- `SONAR_TOKEN` if the same SonarQube token is used across repositories
- `NUGET_API_KEY` if the same publishing key is shared across repositories

### 🔒 Repository secrets
Use repository secrets when a sensitive value is repo-specific:
- `SONAR_TOKEN` if each repository uses a different SonarQube token/project setup
- `NUGET_API_KEY` if each repository publishes to its own feed or uses a separate API key

### ⚙️ Repository variables
Use repository variables for non-sensitive workflow inputs:
- `SOLUTION_NAME`
- `RUNS_ON`
- `SONAR_PROVIDER`
- `SONAR_PROJECT_KEY`
- `SONAR_ORGANIZATION`
- `DOTNET_VERSIONS`
- `USE_GLOBAL_JSON`
- `SHOW_DOTNET_INFO`
- `RUN_RESHARPER_INSPECTCODE`
- `PUBLISH_TEST_RESULTS`
- `PUBLISH_COVERAGE_REPORT`
- `SONAR_HOST_URL`
- `SONAR_SETTINGS_FILE`
- `COVERAGE_SETTINGS_FILE`
- `PACKAGE_OUTPUT_DIRECTORY`
- `NUGET_SOURCE_URL`
- `STRIP_V_PREFIX`

Recommended minimum setup:
- define `SOLUTION_NAME`
- define `SONAR_PROJECT_KEY`
- define `SONAR_ORGANIZATION` if you use SonarCloud
- define the rest only when you want to override workflow defaults

### Quick rule of thumb
- use **secrets** for credentials and tokens
- use **variables** for non-sensitive configuration
- use **organization secrets** only when you intentionally want the same secret shared across repositories

## Suggested developer setup

If you want a clean consumer experience in each repository:

- put shared credentials in **organization secrets**
- put repo-specific credentials in **repository secrets**
- put repo-specific config in **repository variables**

That keeps the calling workflow tiny and easy to understand.
