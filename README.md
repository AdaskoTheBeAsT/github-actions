# AdaskoTheBeAsT github-actions

Reusable GitHub Actions for developers who want clean CI, repeatable releases, and less YAML pain.

## Why this repo exists

These workflows and composite actions help you ship .NET libraries with:
- `dotnet restore`, build, and test
- coverage collection
- SonarCloud or SonarQube analysis
- automatic versioning from git tags
- NuGet packaging and publishing (single or multiple packages per repository)

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
- 📤 packs all packable NuGet projects in the solution (`.nupkg` and `.snupkg`) and uploads them as a workflow artifact for lightweight tags

#### How it behaves
- `pull_request` → build, test, coverage, ReSharper inspect, Sonar pull request analysis
- branch build → build, test, coverage, ReSharper inspect, Sonar branch analysis
- tag build → build, test, coverage, Sonar versioned analysis using `sonar.projectVersion`
- lightweight tag → build, test, Sonar versioned analysis, pack NuGet packages, upload the package artifact (`nuget-packages` by default), and expose workflow outputs for the caller's `publish` job
- annotated tag → skips the package pack and upload path

#### Inputs
- `solution_name` (required): solution to restore, build, test, and pack
- `runs_on`: GitHub Actions runner label, for example `ubuntu-latest` or `windows-latest`
- `sonar_provider`: `sonarcloud` or `sonarqube`, defaults to `sonarcloud`
- `sonar_project_key` (required): Sonar project key
- `sonar_organization`: SonarCloud organization, required when `sonar_provider` is `sonarcloud`
- `dotnet_versions`: comma-separated SDK versions
- `use_global_json`: also install SDK from root `global.json`
- `show_dotnet_info`: run `dotnet --info`
- `runner_type`: `auto` (default), `vstest`, or `mtp`; auto selects MTP when
  root `global.json` sets `test.runner` to `Microsoft.Testing.Platform`
- `run_resharper_inspectcode`: install and run ReSharper InspectCode and include its report in Sonar analysis
- `publish_test_results`: publish TRX results to GitHub checks
- `publish_coverage_report`: generate and publish coverage HTML and workflow summary
- `sonar_host_url`: Sonar server URL, defaults to `https://sonarcloud.io`
- `sonar_settings_file`: path to `SonarQube.Analysis.xml`
- `coverage_settings_file`: path to `coverage.settings.xml`
- `package_output_directory`: pack output directory, defaults to `artifacts/nuget`
- `nuget_artifact_name`: workflow artifact name uploaded when lightweight-tag NuGet packages are packed, defaults to `nuget-packages`
- `strip_v_prefix`: strips `v`/`V` from tags like `v1.2.3`
- `strict_build`: when `true` (default), runs `dotnet build` with `--no-incremental` and `-t:Rebuild` to defeat incremental caching and force every MSBuild target to rerun; disables the class of regressions that only surface after a clean build
- `deterministic_build`: when `true` (default), sets `ContinuousIntegrationBuild=true` as a job-level environment variable so every `dotnet restore`, `build`, `test`, and `pack` call produces deterministic output (stable PDBs, SourceLink paths, no machine-specific timestamps or paths)
- `tool_version_sonar_scanner`: version of the `dotnet-sonarscanner` global tool installed into the cache; empty (the default) resolves and installs the latest stable version from nuget.org, set an explicit version to pin it
- `tool_version_resharper`: version of the `JetBrains.ReSharper.GlobalTools` global tool installed into the cache; empty (the default) resolves and installs the latest stable version from nuget.org, set an explicit version to pin it
- `tool_version_dotnet_coverage`: version of the `dotnet-coverage` global tool installed into the cache; empty (the default) resolves and installs the latest stable version from nuget.org, set an explicit version to pin it
- `tool_version_reportgenerator`: version of the `dotnet-reportgenerator-globaltool` installed into the cache; empty (the default) resolves and installs the latest stable version from nuget.org, set an explicit version to pin it
- `tool_cache_salt`: salt appended to every tool cache key; bump to force a global refresh of all cached .NET global tools independently of a version bump
- `test_frameworks`: comma-separated list of target frameworks to run tests against, for example `net8.0,net9.0`; empty (the default) runs every TFM in the solution
- `test_env`: newline-separated `NAME=VALUE` pairs exported to the test process only; use it for non-sensitive test configuration and see [Passing extra environment variables to the test step](#passing-extra-environment-variables-to-the-test-step)

#### Outputs
- `is_lightweight_tag`: `'true'` when the workflow ran on a lightweight tag and packed NuGet packages; otherwise `'false'`
- `package_version`: version written from the lightweight tag into `Directory.Build.props` (empty when `is_lightweight_tag` is not `'true'`)
- `nuget_artifact_name`: name of the uploaded NuGet package artifact when `is_lightweight_tag` is `'true'` (empty otherwise)

#### Required workflow secrets
- `sonar_token`: required for pull request, branch, and tag builds
- `test_env_secrets`: optional newline-separated `NAME=VALUE` pairs exported to the test process only, for license keys and other credentials the tests need

*(Note: `NUGET_USER` is passed to the calling workflow's `publish` job rather than to `dotnet-build-sonarqube-nuget.yml`; see below.)*

#### NuGet.org Trusted Publishing limitation with reusable workflows
NuGet.org OIDC Trusted Publishing **cannot** be executed directly inside a cross-repository reusable workflow (`uses: AdaskoTheBeAsT/github-actions/.github/workflows/...@v2`).

When `NuGet/login` runs inside a cross-repository reusable workflow, GitHub sets two different repository identities on the OIDC token:
- `repository`: `<Owner>/<ConsumerRepo>` (the repository that triggered the run)
- `job_workflow_ref`: `AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@...` (the shared reusable workflow executing the job)

NuGet.org's token exchange endpoint (`https://www.nuget.org/api/v2/token`) requires **both** `repository` and `job_workflow_ref` to belong to the repository configured in the Trusted Publishing policy, so calling `NuGet/login` from a reusable workflow in another repository fails with `HTTP 401`:
`Claim 'job_workflow_ref' has value 'AdaskoTheBeAsT/github-actions/.github/workflows/...' which does not start with <Owner>/<ConsumerRepo>/.github/workflows/.`
(Generating the short-lived API key in a caller job and passing it into the reusable workflow also does not work because GitHub Actions masks the key as a secret and strips secret values from job outputs.)

To work around this NuGet.org limitation while keeping build and publish logic centralized:
1. `dotnet-build-sonarqube-nuget.yml` packs all packable projects in the solution (`.nupkg` and `.snupkg`) on lightweight tags, uploads them as a workflow artifact (`nuget-packages` by default), and exposes `is_lightweight_tag` and `nuget_artifact_name` outputs.
2. Your repository's workflow defines a small `publish` job (`runs-on:` + `steps:`) with `id-token: write` that invokes the step-level composite action `AdaskoTheBeAsT/github-actions/.github/actions/dotnet/publish-nuget-packages@v2`. Because a composite action runs inside the caller's own job, `job_workflow_ref` points to `<Owner>/<ConsumerRepo>/.github/workflows/<your-workflow>.yml` and satisfies NuGet.org's policy check.
3. On **nuget.org → Trusted Publishing**, configure your policy for the consuming repository:
   - **Repository Owner**: `<Owner>`
   - **Repository**: `<ConsumerRepo>`
   - **Workflow File**: `<your-workflow>.yml` (file name only, for example `ci.yml`, without `.github/workflows/`)
   - **Environment** *(optional)*: leave empty unless you set `environment:` on the `publish` job
   - **Policy Scopes**: select the target package ID(s) or specify a glob pattern (for example `AdaskoTheBeAsT.Interop.*`). Enable new-package creation on the scope if the repository can publish new package IDs.

#### Publishing multiple NuGet packages from one repository
A single repository and solution can produce and publish multiple NuGet packages in one tag run:
- `dotnet pack` packs every packable project (`IsPackable != false`) in `solution_name` using the tag version written to the root `Directory.Build.props`, placing all `.nupkg` and `.snupkg` files into `package_output_directory` and uploading them in one workflow artifact.
- `publish-nuget-packages` downloads that artifact once, runs `NuGet/login` once to obtain a single short-lived API key (valid for 1 hour), and pushes every regular `.nupkg` in the directory with `--skip-duplicate` (while `dotnet nuget push` automatically uploads each package's matching `.snupkg` symbols).
- On NuGet.org, cover all packages produced by that repository in the policy's **Policy Scopes** (either by selecting multiple packages or using a glob pattern such as `MyPrefix.*`).

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
- `RUNNER_TYPE` → defaults to `auto`
- `RUN_RESHARPER_INSPECTCODE` → defaults to `true`
- `PUBLISH_TEST_RESULTS` → defaults to `true`
- `PUBLISH_COVERAGE_REPORT` → defaults to `true`
- `SONAR_HOST_URL` → defaults to `https://sonarcloud.io`
- `SONAR_SETTINGS_FILE` → defaults to `SonarQube.Analysis.xml`
- `COVERAGE_SETTINGS_FILE` → defaults to `coverage.settings.xml`
- `PACKAGE_OUTPUT_DIRECTORY` → defaults to `artifacts/nuget`
- `NUGET_ARTIFACT_NAME` → defaults to `nuget-packages`
- `NUGET_SOURCE_URL` → defaults to `https://api.nuget.org/v3/index.json` (on `.github/actions/dotnet/publish-nuget-packages`)
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
  issues: write
  pull-requests: write

jobs:
  build:
    uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@v2
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
      runner_type: auto
      strict_build: true
      deterministic_build: true
    secrets:
      sonar_token: ${{ secrets.SONAR_TOKEN }}

  publish:
    needs: build
    if: needs.build.outputs.is_lightweight_tag == 'true'
    runs-on: ${{ vars.RUNS_ON || 'ubuntu-latest' }}
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Publish NuGet packages
        uses: AdaskoTheBeAsT/github-actions/.github/actions/dotnet/publish-nuget-packages@v2
        with:
          artifact_name: ${{ needs.build.outputs.nuget_artifact_name }}
          nuget_user: ${{ secrets.NUGET_USER }}
```

#### How to reference the reusable workflow
- use `uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@<ref>` for the `build` job
- add a `publish` job in the same caller workflow (`needs: build`, `if: needs.build.outputs.is_lightweight_tag == 'true'`) that calls `AdaskoTheBeAsT/github-actions/.github/actions/dotnet/publish-nuget-packages@<ref>`
- replace `<ref>` with a branch, tag, or commit SHA such as `v2`, `v2.0.0`, or a pinned SHA
- pass non-sensitive values in `with:`
- pass `sonar_token` (and optional `test_env_secrets`) in `secrets:` on `build`, and pass `NUGET_USER` to `publish`
- neither `build` nor `publish` needs a separate `actions/checkout` step (`build` checks out the repository itself, and `publish` downloads the packed NuGet artifact directly)
- keep `checks: write`, `issues: write`, and `pull-requests: write` permissions on the workflow (or `build` job) so published TRX test results and annotations work
- grant `id-token: write` permission on the `publish` job so `NuGet/login` can request a GitHub OIDC token grounded in the calling workflow's `job_workflow_ref`
- for consumers, prefer `@v2` over `@main` so you can ship backward-compatible updates safely

#### Minimal reference example
```yaml
jobs:
  build:
    uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@v2
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

  publish:
    needs: build
    if: needs.build.outputs.is_lightweight_tag == 'true'
    runs-on: ${{ vars.RUNS_ON || 'ubuntu-latest' }}
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Publish NuGet packages
        uses: AdaskoTheBeAsT/github-actions/.github/actions/dotnet/publish-nuget-packages@v2
        with:
          artifact_name: ${{ needs.build.outputs.nuget_artifact_name }}
          nuget_user: ${{ secrets.NUGET_USER }}
```

#### Test and coverage reporting
- TRX test results are published to GitHub checks
- coverage HTML is uploaded as the `coverage-report` workflow artifact
- a Markdown coverage summary is appended to the workflow summary
- `ReportGenerator` is used to create the HTML report and summary
- `runner_type: vstest` keeps the existing `dotnet-coverage collect` command
- `runner_type: mtp` uses native .NET 10 MTP syntax (`dotnet test --solution`
  and `--report-trx`) inside `dotnet-coverage collect`; dotnet-coverage
  aggregates coverage from all test modules in the solution
- `runner_type: auto` reads the root `global.json`; it selects `mtp` only when
  `test.runner` is `Microsoft.Testing.Platform`, and otherwise selects `vstest`
- MTP test projects must provide the `Microsoft.Testing.Extensions.TrxReport`
  extension for TRX output (it may be included by the selected test SDK profile)
- when MTP runs on GitHub Actions, the test action checks restored
  `project.assets.json` files for
  `Microsoft.Testing.Extensions.GitHubActionsReport`; when found, it adds
  `--report-gh` to enable native annotations, log groups, and the job summary

#### Passing extra environment variables to the test step
Some test suites need extra environment variables at runtime, for example a commercial component license key. GitHub reusable workflows cannot accept a map of inputs or a dynamically named secret, so both channels take a **newline-separated `NAME=VALUE` payload**:

- `test_env` input → non-sensitive values
- `test_env_secrets` secret → sensitive values, masked in the log

```yaml
jobs:
  build:
    uses: AdaskoTheBeAsT/github-actions/.github/workflows/dotnet-build-sonarqube-nuget.yml@v2
    with:
      solution_name: ${{ vars.SOLUTION_NAME }}
      sonar_project_key: ${{ vars.SONAR_PROJECT_KEY }}
      sonar_organization: ${{ vars.SONAR_ORGANIZATION }}
      test_env: |
        MYAPP_TEST_MODE=ci
        MYAPP_TEST_BASE_URL=https://localhost:5001
    secrets:
      sonar_token: ${{ secrets.SONAR_TOKEN }}
      test_env_secrets: |
        DEVEXPRESS_LICENSE=${{ secrets.DEVEXPRESS_LICENSE }}
        ASPOSE_LICENSE_KEY=${{ secrets.ASPOSE_LICENSE_KEY }}
```

- **Scope**: the variables are set in the process that runs `dotnet-coverage collect`, so `dotnet test` and the test host inherit them. They are deliberately **not** written to `$GITHUB_ENV`, so they never leak into the Sonar, pack, or publish steps. They are also not available to the `dotnet build` step, so a license that is checked at *compile* time cannot be supplied this way.
- **Parsing**: one pair per line, split on the first `=`. Name and value are trimmed, blank lines and lines starting with `#` are ignored, and `NAME=` sets an empty value. A line without `=`, or a name that is not a valid environment variable name (`[A-Za-z_][A-Za-z0-9_]*`), fails the step.
- **Masking**: a secret passed into a reusable workflow is masked only as one blob, so the step emits `::add-mask::` for every value it parses out of `test_env_secrets`. Names are logged, values are not.
- **Multi-line values** (a license *file*, a PEM key) do not survive line-based parsing. Base64-encode the value, pass it as a single line, and decode it inside the test setup.
- The raw payloads are removed from the environment before tests start, so the blob itself is never visible to test code.

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

#### .NET global tool versions and caching
The four .NET global tools used by the workflow are installed into version-scoped caches. By default each tool tracks its latest stable release; supply an explicit version to pin it so runs stay byte-for-byte reproducible and upgrades become an auditable diff.

- **Tools managed this way**
  - `dotnet-sonarscanner` → controlled by `tool_version_sonar_scanner`
  - `JetBrains.ReSharper.GlobalTools` → controlled by `tool_version_resharper`
  - `dotnet-coverage` → controlled by `tool_version_dotnet_coverage`
  - `dotnet-reportgenerator-globaltool` → controlled by `tool_version_reportgenerator`

- **An empty version means "latest stable" (and empty is the default)**
  - the `Resolve .NET global tool versions` step runs before the cache steps and, for every `tool_version_*` input that is null/empty/whitespace, queries `https://api.nuget.org/v3-flatcontainer/<package-id>/index.json` and picks the highest non-prerelease version
  - pinned inputs are passed through untouched (only trimmed); nothing is queried for them
  - the resolved version is exposed as a step output and used for both the cache key and `dotnet tool install --version`, so an unpinned tool still gets a version-scoped cache that flips to a new key as soon as a newer release ships
  - the resolved versions are printed in the step log, so every run records exactly which tool versions it used

- **How the cache key is built**
  - `${{ runner.os }}-<tool>-<resolved-version>-<tool_cache_salt>`
  - the install step uses `dotnet tool install --version "<resolved-version>"` so the cache contents exactly match the version in the key
  - cache hit → install step is skipped; cache miss → that version is installed and the cache is saved under the new key

- **How to pick up a new release of a tool**
  - unpinned (the default): nothing to do, the next run resolves the newer version, cache-misses on the new key and installs it
  - pinned: find the new stable version on NuGet, bump the corresponding `TOOL_VERSION_*` repository/organization variable (or the input in the caller workflow); the next run cache-misses on the new key and installs it, and the old cache entry is evicted by GitHub's LRU/age policy

- **Emergency-invalidate every tool cache at once**
  - bump `TOOL_CACHE_SALT` (for example from `v1` to `v2`) without changing any version
  - all four tool caches miss on the next run and reinstall
  - useful when a cache was poisoned or when rolling out across many consumer repos quickly

- **Why this matters for a reusable workflow**
  - out of the box every caller stays current instead of being silently stuck on "whatever was latest on day one"
  - any caller repo that needs stability can pin its own versions via `vars.TOOL_VERSION_*`, making upgrades auditable PR diffs rather than invisible cache contents
  - either way the cache key carries the concrete resolved version, so cached contents always match what was requested
  - a scheduled bump PR can track pinned versions without touching workflow YAML

## Composite actions

### 🏷️ `.github/actions/dotnet/detect-lightweight-tag`
Detects whether a ref points to a lightweight git tag and exposes `is_lightweight_tag`.

### 🧰 `.github/actions/dotnet/setup-dotnet-sdks`
Installs one or more .NET SDK versions. Supports explicit SDK versions and/or the root `global.json`.

### 🔢 `.github/actions/dotnet/set-directory-build-props-version-from-tag`
Writes the tag version into the root `Directory.Build.props` `<Version>` element and returns the resolved version.

### 📤 `.github/actions/dotnet/publish-nuget-packages`
Publishes all regular `.nupkg` packages in `package_output_directory` (skipping standalone `.snupkg` and `.symbols.nupkg` files so `dotnet nuget push` pushes sibling `.snupkg` symbols automatically). Designed to run inside a job defined in the calling repository's workflow so GitHub's `job_workflow_ref` OIDC claim matches NuGet.org's Trusted Publishing policy.

#### Inputs
- `package_output_directory`: directory containing (or receiving downloaded) NuGet packages, defaults to `artifacts/nuget`
- `artifact_name`: optional workflow artifact name to download into `package_output_directory` before publishing (for example `${{ needs.build.outputs.nuget_artifact_name }}`), defaults to empty
- `nuget_source_url`: NuGet feed URL, defaults to `https://api.nuget.org/v3/index.json`
- `nuget_user`: NuGet.org profile username (not email address) used with `NuGet/login` for OIDC Trusted Publishing; provide either `nuget_user` or `nuget_api_key`
- `nuget_api_key`: explicit NuGet API key for feeds that do not use NuGet.org OIDC Trusted Publishing; provide either `nuget_user` or `nuget_api_key`
- `nuget_token_service_url`: token exchange URL passed to `NuGet/login`, defaults to `https://www.nuget.org/api/v2/token`
- `nuget_audience`: OIDC audience requested by `NuGet/login`, defaults to `https://www.nuget.org`

## Secrets and variables setup

The reusable workflow receives build and Sonar inputs through `with:` and `secrets:`, while the caller workflow's `publish` job passes `NUGET_USER` to `.github/actions/dotnet/publish-nuget-packages`.

### 🔐 Organization secrets
Use organization secrets for sensitive values shared across multiple repositories:
- `SONAR_TOKEN` if the same SonarQube token is used across repositories
- `NUGET_USER` if the same nuget.org profile username is used across repositories for Trusted Publishing

### 🔒 Repository secrets
Use repository secrets when a sensitive value is repo-specific:
- `SONAR_TOKEN` if each repository uses a different SonarQube token/project setup
- `NUGET_USER` if each repository publishes under a different nuget.org profile username

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
- `RUNNER_TYPE`
- `RUN_RESHARPER_INSPECTCODE`
- `PUBLISH_TEST_RESULTS`
- `PUBLISH_COVERAGE_REPORT`
- `SONAR_HOST_URL`
- `SONAR_SETTINGS_FILE`
- `COVERAGE_SETTINGS_FILE`
- `PACKAGE_OUTPUT_DIRECTORY`
- `NUGET_ARTIFACT_NAME`
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
