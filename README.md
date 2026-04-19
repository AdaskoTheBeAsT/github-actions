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
- `strict_build`: when `true` (default), runs `dotnet build` with `--no-incremental` and `-t:Rebuild` to defeat incremental caching and force every MSBuild target to rerun; disables the class of regressions that only surface after a clean build
- `deterministic_build`: when `true` (default), sets `ContinuousIntegrationBuild=true` as a job-level environment variable so every `dotnet restore`, `build`, `test`, and `pack` call produces deterministic output (stable PDBs, SourceLink paths, no machine-specific timestamps or paths)
- `tool_version_sonar_scanner`: pinned version of the `dotnet-sonarscanner` global tool installed into the cache
- `tool_version_resharper`: pinned version of the `JetBrains.ReSharper.GlobalTools` global tool installed into the cache
- `tool_version_dotnet_coverage`: pinned version of the `dotnet-coverage` global tool installed into the cache
- `tool_version_reportgenerator`: pinned version of the `dotnet-reportgenerator-globaltool` installed into the cache
- `tool_cache_salt`: salt appended to every tool cache key; bump to force a global refresh of all cached .NET global tools independently of a version bump

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
- `STRICT_BUILD` → defaults to `true`
- `DETERMINISTIC_BUILD` → defaults to `true`
- `TOOL_VERSION_SONAR_SCANNER` → defaults to the latest stable `dotnet-sonarscanner`
- `TOOL_VERSION_RESHARPER` → defaults to the latest stable `JetBrains.ReSharper.GlobalTools`
- `TOOL_VERSION_DOTNET_COVERAGE` → defaults to the latest stable `dotnet-coverage`
- `TOOL_VERSION_REPORTGENERATOR` → defaults to the latest stable `dotnet-reportgenerator-globaltool`
- `TOOL_CACHE_SALT` → defaults to `v1`

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
    uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@v1
    with:
      solution_name: ${{ vars.SOLUTION_NAME }}
      runs_on: ${{ vars.RUNS_ON }}
      sonar_provider: ${{ vars.SONAR_PROVIDER }}
      sonar_project_key: ${{ vars.SONAR_PROJECT_KEY }}
      sonar_organization: ${{ vars.SONAR_ORGANIZATION }}
      dotnet_versions: ${{ vars.DOTNET_VERSIONS }}
      tool_version_dotnet_coverage: ${{ vars.TOOL_VERSION_DOTNET_COVERAGE }}
      tool_version_reportgenerator: ${{ vars.TOOL_VERSION_REPORTGENERATOR }}
      tool_version_resharper: ${{ vars.TOOL_VERSION_RESHARPER }}
      tool_version_sonar_scanner: ${{ vars.TOOL_VERSION_SONAR_SCANNER }}
      use_global_json: true
      strict_build: true
      deterministic_build: true
    secrets:
      sonar_token: ${{ secrets.SONAR_TOKEN }}
      nuget_api_key: ${{ secrets.NUGET_API_KEY }}
```

#### How to reference the reusable workflow
- use `uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@<ref>`
- replace `<ref>` with a branch, tag, or commit SHA such as `v1`, `v1.0.0`, or a pinned SHA
- pass non-sensitive values in `with:`
- pass tokens and credentials in `secrets:`
- do not add a separate checkout step in the calling job unless you have another job outside this reusable workflow that needs it
- keep `checks: write` permission if you want published TRX test results to appear in GitHub checks

- for consumers, prefer `@v1` over `@main` so you can ship backward-compatible updates safely

#### Minimal reference example
```yaml
jobs:
  ci:
    uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@v1
    with:
      solution_name: ${{ vars.SOLUTION_NAME }}
      runs_on: ${{ vars.RUNS_ON }}
      sonar_provider: ${{ vars.SONAR_PROVIDER }}
      sonar_project_key: ${{ vars.SONAR_PROJECT_KEY }}
      sonar_organization: ${{ vars.SONAR_ORGANIZATION }}
      dotnet_versions: ${{ vars.DOTNET_VERSIONS }}
      tool_version_dotnet_coverage: ${{ vars.TOOL_VERSION_DOTNET_COVERAGE }}
      tool_version_reportgenerator: ${{ vars.TOOL_VERSION_REPORTGENERATOR }}
      tool_version_resharper: ${{ vars.TOOL_VERSION_RESHARPER }}
      tool_version_sonar_scanner: ${{ vars.TOOL_VERSION_SONAR_SCANNER }}
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

#### Build hygiene (`strict_build`, `deterministic_build`)
Two inputs control how aggressively CI invalidates caches and how reproducible the produced binaries are.

- **`strict_build`** (default `true`)
  - Adds `--no-incremental -t:Rebuild` to the `dotnet build` invocation.
  - `--no-incremental` disables MSBuild's target-skipping so every target reruns.
  - `-t:Rebuild` invokes a Clean + Build top-level target, making sure that stale `obj`/`bin` artifacts from a previous job do not influence the current build.
  - Together they defeat the class of regressions that pass on a cached incremental build but fail on a clean one (for example a `#pragma warning disable` for a *compile error* that only manifests on a full rebuild).
  - Set to `false` on very large solutions when build time is more important than guaranteed freshness.

- **`deterministic_build`** (default `true`)
  - Sets the MSBuild property `ContinuousIntegrationBuild=true` as a **job-level environment variable**, so every `dotnet restore`, `build`, `test`, and `pack` call in the job inherits it automatically.
  - Enables MSBuild's deterministic build contract: stable PDB paths, embedded SourceLink paths, no machine-specific timestamps, reproducible NuGet package hashes.
  - Recommended for anything that publishes NuGet packages so consumers can diff binaries reliably.

- These switches affect only the **build** step. `dotnet pack` is not given `-t:Rebuild` because that would wipe and re-emit signed assemblies right after the Build step produced them; it still picks up `ContinuousIntegrationBuild=true` from job env, so the packed output remains deterministic.

#### Pinned .NET global tool versions and caching
The four .NET global tools used by the workflow are installed into version-scoped caches so CI runs are reproducible and upgrades are explicit.

- **Tools managed this way**
  - `dotnet-sonarscanner` → controlled by `tool_version_sonar_scanner`
  - `JetBrains.ReSharper.GlobalTools` → controlled by `tool_version_resharper`
  - `dotnet-coverage` → controlled by `tool_version_dotnet_coverage`
  - `dotnet-reportgenerator-globaltool` → controlled by `tool_version_reportgenerator`

- **How the cache key is built**
  - `${{ runner.os }}-<tool>-<tool_version_*>-<tool_cache_salt>`
  - the install step uses `dotnet tool install --version "<tool_version_*>"` so the cache contents exactly match the requested version
  - cache hit → install step is skipped; cache miss → the pinned version is installed and the cache is saved under the new key

- **How to pick up a new release of a tool**
  1. find the new stable version on NuGet
  2. bump the corresponding `TOOL_VERSION_*` repository/organization variable (or the input in the caller workflow)
  3. next run will cache-miss on the new key and install the new version
  4. the old cache entry is evicted by GitHub's LRU/age policy

- **Emergency-invalidate every tool cache at once**
  - bump `TOOL_CACHE_SALT` (for example from `v1` to `v2`) without changing any version
  - all four tool caches miss on the next run and reinstall
  - useful when a cache was poisoned or when rolling out across many consumer repos quickly

- **Why this matters for a reusable workflow**
  - every caller repo can keep its own pinned versions via `vars.TOOL_VERSION_*`
  - builds become reproducible across runs — you are not silently stuck on "whatever was latest on day one"
  - upgrades are auditable PR diffs, not invisible cache contents
  - Dependabot or a scheduled bump PR can track these versions without touching workflow YAML

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
- `STRICT_BUILD`
- `DETERMINISTIC_BUILD`
- `TOOL_VERSION_SONAR_SCANNER`
- `TOOL_VERSION_RESHARPER`
- `TOOL_VERSION_DOTNET_COVERAGE`
- `TOOL_VERSION_REPORTGENERATOR`
- `TOOL_CACHE_SALT`

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
