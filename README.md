# OceanData

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ruirojo.github.io/OceanData.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ruirojo.github.io/OceanData.jl/dev)
[![CI](https://github.com/RuiRojo/OceanData.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/RuiRojo/OceanData.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/RuiRojo/OceanData.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/RuiRojo/OceanData.jl)

Lightweight Julia helpers to access Copernicus Marine (CMEMS) global fields and build ocean profiles with units. Retrieve temperature, salinity, and sound speed anywhere on the globe, work with Unitful quantities, and generate vertical profiles on standard depths. Includes a convenience `bathymetry` query.

## Highlights
- Simple API returning Unitful quantities where appropriate
- Point queries and curried forms (returning functions of depth)
- Ready-made vertical sampling levels (`standard_depths`) and profile helpers
- On-demand downloads via Copernicus Marine CLI, cached locally with DataDeps
- Explicit control over date and near-seabed handling of missing data (`extend=true`)

## Installation
Requires Julia ≥ 1.6.

- If registered:
  ```julia
  pkg> add OceanData
  ```
- Otherwise from GitHub:
  ```julia
  pkg> add https://github.com/RuiRojo/OceanData.jl
  ```

You will need a free Copernicus Marine account to download data.

## Quick start
```julia
using OceanData

loc  = (-45°, -40°)               # (latitude, longitude) with units
date = Date(2017, 12, 1)

T = temperature(loc, 100m; date)   # → Quantity in °C
S = salinity(loc, 100m; date)      # → dimensionless (psu ≈ g/kg)
c = soundspeed(loc, 100m; date)    # → Quantity in m/s

cz = soundspeed(loc; date)         # curried form: z ↦ c(z)
cz(500m)

# Handling seabed: values below the seabed are `missing` unless you choose to extend
Tdeep = temperature(loc, 6000m; date)                 # → missing
Text  = temperature(loc, 6000m; date, extend=true)    # → held-constant extension
```
Notes:
- Coordinates are in the order `(latitude, longitude)` and must carry units (use `°`).
- Depths must be non-negative and unitful (e.g., `m`).
- Pass `date=Date(yyyy,mm,dd)` to avoid log messages and ensure reproducibility.

## Vertical profiles
```julia
cz   = soundspeed(loc; date=d)
prof = makeprofile(cz)                 # samples on `standard_depths` up to 8000 m

# Customize depth range or sampling grid
prof = makeprofile(cz; zmax=3000m)     # cap at 3000 m
prof = makeprofile(cz; zs=[0m, 10m, 25m, 50m, 100m])

first(prof, 3)  # Vector of (depth, value) pairs
```
`standard_depths` is a vector of depths spaced finer near the surface, read from `src/depths.dat`.

## Refraction index
```julia
n100 = refraction_index(loc, 100m; date)              # at a depth (default c0=1500 m/s)
nz   = refraction_index(loc; date)                    # returns z ↦ n(z)
```

## Bathymetry
```julia
h = bathymetry(loc)                                     # positive depth in meters offshore
bathymetry((3°, 15°); nothrow=true)                     # → missing on land
```

## Data sources and date control
By default OceanData uses the CMEMS GREP monthly-statistics daily product; you can switch to GLORYS12 if desired.

- Default database: `GREP_MNSTD` (daily means)
  - Date coverage: 1993-01-01 … 2025-12-31
  - Variables: temperature `thetao_mean`, salinity `so_mean`
  - Dataset id: `cmems_mod_glo_phy-mnstd_my_0.25deg_P1D-m`
- Optional database: `GLORYS12` (daily)
  - Date coverage: 1991-12-04 … 2021-12-31
  - Variables: temperature `thetao`, salinity `so`
  - Dataset id: `cmems_mod_glo_phy_my_0.083deg_P1D-m` (or `..._myint_...` after 2021-06-30)

Switch database at runtime:
```julia
using OceanData.Copernicus: switch_database
switch_database("GLORYS12")   # or "GREP_MNSTD"
```
Always pass the `date` keyword to `temperature`/`salinity`/`soundspeed` (or their curried forms) to control which day’s fields are used.

## Downloading and caching
Data are downloaded on first use for a given date via the Copernicus Marine CLI and cached by DataDeps under your Julia depot (e.g., `~/.julia/datadeps/`). Repeated calls reuse the cached file. You will be prompted for CMEMS credentials once unless provided non-interactively (see below).

## Copernicus Marine CLI resolution
OceanData locates the `copernicusmarine` executable in this order:

1. A build-time constant written to `deps/deps.jl` (set by `Pkg.build("OceanData")`) if it points to an executable
2. Environment variable `COPERNICUSMARINE_CLI` if it points to an executable
3. A Julia artifact named `copernicusmarine_cli` (if present via LazyArtifacts)
4. `copernicusmarine` found on `PATH`

If none is found, an error is raised.

### Non-interactive credentials
Set these environment variables to avoid interactive prompts:
- `COPERNICUSMARINE_USERNAME`
- `COPERNICUSMARINE_PASSWORD`

### Auto-provision (build)
`Pkg.build("OceanData")` will attempt to download a prebuilt Copernicus CLI for your platform and bind it as a Julia artifact, taking glibc version into account on Linux. It writes `deps/deps.jl` with the resolved path. To skip this, set `OCEANDATA_SKIP_CLI_BUILD=1`. You can always override with `COPERNICUSMARINE_CLI`.

If you prefer to install manually, use `pipx install copernicusmarine` and ensure the executable is on `PATH` or set `COPERNICUSMARINE_CLI` to its full path.

## API overview
- `temperature((lat, lon), z; date, extend=false) → °C or missing`
- `salinity((lat, lon), z; date, extend=false) → Float32 or missing`
- `soundspeed((lat, lon), z; date, extend=false) → m/s or missing`
- Curried forms: `temperature(loc; ...)`, `salinity(loc; ...)`, `soundspeed(loc; ...)` return functions `z ↦ value`
- `makeprofile(pfun; zmax=8000m, zs=standard_depths) → Vector{Tuple{depth, value}}`
- `standard_depths::Vector{<:Unitful.Length}`
- `refraction_index(c::Unitful.Velocity; c0=1500m/s)` and location-based variants
- `bathymetry((lat, lon); nothrow=false) → meters (positive offshore) or missing`

All inputs are unitful: use `°` for angles and `m` for depths. Longitude is ignored for sound speed physics but kept for interpolation consistency.

## Troubleshooting
- CLI not found: run `Pkg.build("OceanData")`, set `ENV["COPERNICUSMARINE_CLI"]`, or install the CLI so it’s on `PATH`.
- Linux glibc: the build script picks a CLI binary compatible with your glibc (2.35 or 2.39). If your platform is unsupported, install the CLI yourself and set `COPERNICUSMARINE_CLI`.
- Authentication: set `COPERNICUSMARINE_USERNAME` and `COPERNICUSMARINE_PASSWORD` to avoid prompts in non-interactive environments.
- Seabed values: use `extend=true` to hold last valid layer constant below the seabed; otherwise you will get `missing`.
- Coordinate order: pass `(latitude, longitude)` with units, e.g. `(-45°, -40°)`.


## License
This package is licensed under the MIT License. See `LICENSE`.
