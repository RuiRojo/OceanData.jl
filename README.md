# OceanData

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://das-ara/priv/julia.gitlab.io/OceanData.jl/dev)
[![Build Status](https://gitlab.com/das-ara/priv/julia/OceanData.jl/badges/master/pipeline.svg)](https://gitlab.com/das-ara/priv/julia/OceanData.jl/pipelines)
[![Coverage](https://gitlab.com/das-ara/priv/julia/OceanData.jl/badges/master/coverage.svg)](https://gitlab.com/das-ara/priv/julia/OceanData.jl/commits/master)


## Copernicus Marine CLI resolution

OceanData downloads Copernicus CMEMS subsets using the Copernicus Marine CLI. The executable is resolved in this order:

1. `ENV["COPERNICUSMARINE_CLI"]` if it points to an executable
2. Artifact named `copernicusmarine_cli` if present (via Julia LazyArtifacts)
3. `copernicusmarine` found on PATH

If none is found, an error is raised.

To use an artifact, define it in `Artifacts.toml` at the repository root with the key `copernicusmarine_cli`. Alternatively, install the CLI with `pipx install copernicusmarine` and ensure it is on PATH, or set `COPERNICUSMARINE_CLI` to the full path of the executable.

### Non-interactive credentials

Set these environment variables to avoid interactive prompts:

- `COPERNICUSMARINE_USERNAME`
- `COPERNICUSMARINE_PASSWORD`

### Auto-provision (build)

`Pkg.build("OceanData")` will attempt to download a prebuilt Copernicus CLI for your platform and bind it as a Julia artifact, taking glibc version into account on Linux. It writes `deps/deps.jl` with the resolved path. To skip this, set `OCEANDATA_SKIP_CLI_BUILD=1`. You can always override with `COPERNICUSMARINE_CLI`.
