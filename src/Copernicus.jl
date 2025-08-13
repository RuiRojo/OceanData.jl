module Copernicus

using NCDatasets, Interpolations
using DataDeps
using Dates: Date, Day, day, month, year, dayofweek
using ArgCheck
using Unitful
using Unitful: Length, m, s, °C
using Logging
using Geo
using LazyArtifacts

export temperature, salinity, soundspeed
export makeprofile
export standard_depths
export m, s, °C
export Date

# Try to load provisioned paths from deps/deps.jl if present
const _ocean_deps_loaded = let f = joinpath(@__DIR__, "..", "deps", "deps.jl")
    if isfile(f)
        include(f)
        true
    else
        false
    end
end


"The current date of the loaded database"
date :: Union{Nothing, Date} = nothing

"Whether the loaded database is extended or has missing values where the seabed is"
extend = false

"Default surface temperature for points where it is missing"
const temp0 = 12.0

"Default surface salinity for points where it is missing"
const sal0 = 34.0


# Check. this is duplicated in RAMTools
const Profile{T<:Union{Number, Unitful.Quantity}} = AbstractVector{<:Tuple{Length, T}}

copernicus_credentials = nothing

get_cm_credentials() = begin
    global copernicus_credentials
    if !isnothing(copernicus_credentials)
        return copernicus_credentials
    end
    if haskey(ENV, "COPERNICUSMARINE_USERNAME") && haskey(ENV, "COPERNICUSMARINE_PASSWORD")
        copernicus_credentials = (ENV["COPERNICUSMARINE_USERNAME"], ENV["COPERNICUSMARINE_PASSWORD"])
        return copernicus_credentials
    end
    println("Copernicus credentials:")
    println("username: "); username = readline()
    sbuf = Base.getpass("password")
    password = read(sbuf, String)
    Base.shred!(sbuf)
    copernicus_credentials = username, password
    println("Downloading data. Please wait...")
    return copernicus_credentials
end

# Locate Copernicus Marine CLI (env var, artifact, then PATH)
cm_cli() = begin
    # 1) deps/deps.jl (written by build) sets COPERNICUSMARINE_CLI
    if isdefined(@__MODULE__, :COPERNICUSMARINE_CLI) && Sys.isexecutable(getfield(@__MODULE__, :COPERNICUSMARINE_CLI))
        return getfield(@__MODULE__, :COPERNICUSMARINE_CLI)
    end
    # 2) environment variable
    if haskey(ENV, "COPERNICUSMARINE_CLI") && Sys.isexecutable(ENV["COPERNICUSMARINE_CLI"])
        return ENV["COPERNICUSMARINE_CLI"]
    end
    # 3) artifact fallback (if present without deps)
    try
        exe = joinpath(artifact"copernicusmarine_cli", Sys.iswindows() ? "copernicusmarine.exe" : "copernicusmarine")
        Sys.isexecutable(exe) && return exe
    catch
    end
    # 4) PATH
    exe = Sys.which("copernicusmarine")
    isnothing(exe) && error("Copernicus Marine CLI not found. Run Pkg.build(OceanData), set ENV['COPERNICUSMARINE_CLI'], or install via pip.")
    return exe
end

function fetch_with_cli(rem, loc)
    # rem format: "cmtoolbox|<DB>|<YYYY-MM-DD>|<outfile.nc>"
    parts = split(rem, "|")
    @assert length(parts) == 4 "Invalid remote descriptor: $rem"
    _, db, dstr, outfile = parts
    d = Date(dstr)
    vars = if db == "GREP_MNSTD"
        ["thetao_mean", "so_mean"]
    elseif db == "GLORYS12"
        ["thetao", "so"]
    else
        error("Unknown DB $db")
    end
    dataset_id = if db == "GREP_MNSTD"
        "cmems_mod_glo_phy-mnstd_my_0.25deg_P1D-m"
    elseif db == "GLORYS12"
        if d <= Date(2021, 6, 30)
            "cmems_mod_glo_phy_my_0.083deg_P1D-m"
        else
            "cmems_mod_glo_phy_myint_0.083deg_P1D-m"
        end
    end

    username, password = get_cm_credentials()

    isdir(loc) || mkpath(loc)
    cli = cm_cli()
    cmd = `$(cli) subset --dataset-id $(dataset_id) --start-datetime $(string(d)) --end-datetime $(string(d)) --output-directory $(loc) --output-filename $(outfile) --username $(username) --password $(password)`
    for v in vars
        cmd = `$cmd --variable $(v)`
    end
    run(cmd)
    return joinpath(loc, outfile)
end

function __init__()

    global date = nothing

    # GREP mnstd (closest to old GREPv2 mnstd), daily
    function reg_grep(d)
        name = "grep_temp-sal-$(d)"
        outf = fname_grep(d)
        rem = "cmtoolbox|GREP_MNSTD|$(d)|$(outf)"
        register(DataDep(name,
            """
            Copernicus GREP mnstd temperature and salinity data for $d.
            """,
            rem;
            fetch_method=fetch_with_cli
        ))
    end

    # GLORYS12 daily
    function reg_glorys(d)
        name = "glorys_temp-sal-$(d)"
        outf = fname_glorys(d)
        rem = "cmtoolbox|GLORYS12|$(d)|$(outf)"
        register(DataDep(name,
            """
            Copernicus GLORYS12 temperature and salinity data for $d.
            """,
            rem;
            fetch_method=fetch_with_cli
        ))
    end

    for d in Date(1993, 1, 1):Day(1):Date(2025, 12, 31)
        reg_grep(d)
    end
    for d in Date(1991, 12, 4):Day(1):Date(2021, 12, 31)
        reg_glorys(d)
    end
end

COPERNICUS_DB = "GREP_MNSTD"

const DATABASES = ["GREP_MNSTD", "GLORYS12"];

function switch_database(st)
    @assert st ∈ DATABASES "Database has to be one of $DATABASES"

    global date = nothing
    global COPERNICUS_DB = st

    return nothing
end

# Functions to manage the database files
fname_grep(d) = "grep_tso_$(replace(string(d), "-"=>"" )).nc"
fname_glorys(d) = "glorys_tso_$(replace(string(d), "-"=>"" )).nc"

ddep(d) = if COPERNICUS_DB == "GREP_MNSTD"
    @datadep_str("grep_temp-sal-$d/$(fname_grep(d))") 
elseif COPERNICUS_DB == "GLORYS12"
    @datadep_str("glorys_temp-sal-$d/$(fname_glorys(d))")
end


"Set the database to extend the profiles."
function setextend(b)
        # Only process if there's something to change
    extend == b && return

    if b # If we need to extend, extend
        datamat = cache[:temperature].itp.coefs #itemp.itp.coefs
        
        # Just to remove all the missings
        for i in CartesianIndices(axes(datamat)[1:2])
            !ismissing(datamat[i, 1]) && continue
            datamat[i, 1] = temp0
        end

        for i in CartesianIndices(axes(datamat)[1:2]), j in 2:size(datamat, 3)
            !ismissing(datamat[i, j]) && continue
            datamat[i, j] = datamat[i, j-1]
        end

        datamat = cache[:salinity].itp.coefs #isal.itp.coefs
        #
        # Just to remove all the missings
        for i in CartesianIndices(axes(datamat)[1:2])
            !ismissing(datamat[i, 1]) && continue
            datamat[i, 1] = sal0
        end

        for i in CartesianIndices(axes(datamat)[1:2]), j in 2:size(datamat, 3)
            !ismissing(datamat[i, j]) && continue
            datamat[i, j] = datamat[i, j-1]
        end

        haskey(cache, :soundspeed) && cache_soundspeed()
    else # If we need to un-extend, re-load the data.
        loaddata(getdate())
    end
    global extend = b

    return nothing
end

const default_date = Date(2017, 12, 1)

getdate() = date

function setdate(d::Date)
    d == getdate() && return nothing

    loaddata(d)

    return nothing
end

function with_cached_soundspeed(fun, date; extend=true)
    cache_soundspeed(date; extend)
    out = fun()
    uncache_soundspeed()
    return out
end
function uncache_soundspeed() 
    global cache
    delete!(cache, :soundspeed)
    return nothing
end
function cache_soundspeed(date; extend)
    temperature((0°, 0°), 2m; date, extend)

    lons_u, lats_u, zs_u = cache[:temperature].itp.knots
    sals  = let
        s = cache[:salinity].itp.coefs
        sz = cat(s[:, :, 1:1], s, s[:, :, end:end]; dims=3)
        szlon = cat(sz, sz[1:1, :, :]; dims=1)
        cat(szlon[:, end:end, :], szlon; dims=2)
    end
    temps  = let
        t = cache[:temperature].itp.coefs .* °C
        tz = cat(t[:, :, 1:1], t, t[:, :, end:end]; dims=3)
        tzlon = cat(tz, tz[1:1, :, :]; dims=1)
        cat(tzlon[:, end:end, :], tzlon; dims=2)
    end
    lats = pushfirst!(Float64.(lats_u) .* °, -90.0°)
    lons = push!(Float64.(lons_u) .* °, 180.0°)
    zs = Float64.(zs_u) .* m; pushfirst!(zs, 0.0m); push!(zs, 50000.0m)

    nlon, nlat, nz = size(temps)
    cache[:soundspeed]  = interpolate(
                (lats, lons, zs), 
                [ 
                    leroy(sals[ilon, ilat, iz], temps[ilon, ilat, iz], zs[iz], lats[ilat]) 
                    for ilat in 1:nlat, ilon in 1:nlon, iz in 1:nz  ], 
                Gridded(Linear()))
    @eval const SST = typeof(cache[:soundspeed])
    return nothing
end

const iT = Interpolations.Extrapolation{Missing, 3, Interpolations.GriddedInterpolation{Missing, 3, Array{Union{Missing, Float16}, 3}, Gridded{Linear{Throw{OnGrid}}}, Tuple{Vector{Float32}, Vector{Float32}, Vector{Float32}}}, Gridded{Linear{Throw{OnGrid}}}, Flat{Nothing}}
#global isal  :: iT
#global itemp :: iT

const cache = Dict{Symbol, AbstractInterpolation #=iT=#}()

# Ensure variable arrays are ordered as (lon, lat, depth, time) before dropping time
function _reorder_to_lon_lat_depth_time(ds, varname)
    v = ds[varname]
    # Get dimension names for the variable
    dnames = String.(dimnames(v))
    # Map from name to axis position in current array
    arr = v[:, :, :, :]  # materialize to get array with all dims
    # Determine permutation that brings (lon, lat, depth, time)
    # Known coordinate names in CMEMS: "longitude", "latitude", "depth", "time"
    name_to_target = Dict(
        "longitude" => 1,
        "latitude"  => 2,
        "depth"     => 3,
        "time"      => 4,
    )
    perm = Vector{Int}(undef, length(dnames))
    for (i, nm) in enumerate(dnames)
        @assert haskey(name_to_target, nm) "Unexpected dimension name '$nm' in variable '$varname'"
        perm[i] = name_to_target[nm]
    end
    # perm now tells target position for each current axis; build invperm to permute current -> target order
    invp = Vector{Int}(undef, length(perm))
    for i in 1:length(perm)
        invp[perm[i]] = i
    end
    permutedims(arr, Tuple(invp))
end

function loaddata(d)
    ds = Dataset(ddep(d))

    Type = Float16
    toType(x) = convert(Array{Union{Missing, Type}}, x)

    temp_var = if COPERNICUS_DB == "GREP_MNSTD"
        "thetao_mean"
    elseif COPERNICUS_DB == "GLORYS12"
        "thetao"
    end
    sal_var = if COPERNICUS_DB == "GREP_MNSTD"
        "so_mean"
    elseif COPERNICUS_DB == "GLORYS12"
        "so"
    end
    lats = ds["latitude"][:]
    lons = ds["longitude"][:]
    izs   = ds["depth"][:]

    # Reorder to (lon, lat, depth, time) then drop time
    T4 = _reorder_to_lon_lat_depth_time(ds, temp_var)
    S4 = _reorder_to_lon_lat_depth_time(ds, sal_var)
    temps = T4[:, :, :, 1] |> toType
    sals  = S4[:, :, :, 1]  |> toType

        # It also has the standard deviations
    global extend = false
    Logging.with_logger(Logging.NullLogger()) do 
        itemp = extrapolate(interpolate((lons, lats, izs), temps, Gridded(Linear())), Flat())
        isal  = extrapolate(interpolate((lons, lats, izs), sals, Gridded(Linear())), Flat())
        push!(cache, :temperature => itemp)
        push!(cache, :salinity => isal)
    end

    global date = d

    GC.gc()
end



"""
    temperature(loc, z; date, extend=false)

Return the temperature at geo-location `loc` and depth `z`.

# Keyword arguments

- `extend` determines whether missing values --typically under the seabed but not always--
should be extended by holding temperature constant. Actually, temperature is held constant only
at the locations for which the original grid has data, and other values get interpolated for that;
which means at most positions the temperature returned won't be a constant within the seabed.

- `date` isn't actually necessary. If it is not supplied, the currently loaded date
is used, with a warning every time. It is recommended to pass an explicit date, represented
by a `Dates.Date` obect: e.g., `Date(2017,12,1)`.

# Example

```jldoctest
julia> using OceanData

julia> temperature((-54°, -45°), 100m; date=Date(2017, 12, 1))
2.122145f0 °C

julia> temperature((-54°, -45°), 10000m; date=Date(2017, 12, 1))
missing

julia> temperature((-54°, -45°), 10000m; date=Date(2017, 12, 1), extend=true)
0.45288086f0 °C
```
"""
temperature((lat, lon), z::Length; date=nothing, extend=false) = withdate(date) do
    @assert z >= zero(z) "Depths must be given as non-negative"
    Geo.checkgeopos((lat, lon))
    lat_u, lon_u = ustrip.((lat, lon))
    z_u = ustrip(m, z)
    setextend(extend)
   
    try
        #itemp(lon_u, lat_u, z_u) * °C
        cache[:temperature](lon_u, lat_u, z_u) * °C
    catch
        missing
    end
end

"""
    salinity(loc, z; date, extend=false)

Return the salinity at geo-location `loc` and depth `z`.

# Keyword arguments

- `extend` determines whether missing values --typically under the seabed but not always--
should be extended by holding salinity constant. Actually, temperature is held constant only
at the locations for which the original grid has data, and other values get interpolated for that;
which means at most positions the salinity returned won't be a constant within the seabed.

- `date` isn't actually necessary. If it is not supplied, the currently loaded date
is used, with a warning every time. It is recommended to pass an explicit date, represented
by a `Dates.Date` obect: e.g., `Date(2017,12,1)`.

# Example

```jldoctest
julia> using OceanData

julia> salinity((-54°, -45°), 100m; date=Date(2017, 12, 1))
33.96875f0

julia> salinity((-54°, -45°), 10000m; date=Date(2017, 12, 1))
missing

julia> salinity((-54°, -45°), 10000m; date=Date(2017, 12, 1), extend=true)
34.6875f0
```
"""
salinity((lat, lon), z::Length; date=nothing, extend=false) = withdate(date) do
    @assert z >= zero(z) "Depths must be given as non-negative"
    Geo.checkgeopos((lat, lon))
    lat_u, lon_u = ustrip.((lat, lon))
    z_u = ustrip(m, z)

    setextend(extend)

    try
        #isal(lon_u, lat_u, z_u)
        cache[:salinity](lon_u, lat_u, z_u)
    catch
        missing
    end
end


"""  
    soundspeed(loc, z; date, extend=false)

Return the sound speed at geo-location `loc` and depth `z`.

# Keyword arguments

- `extend` determines whether missing values --typically under the seabed but not always--
should be extended by holding temperature and salinity constants. 

- `date` isn't actually necessary. If it is not supplied, the currently loaded date
is used, with a warning every time. It is recommended to pass an explicit date, represented
by a `Dates.Date` obect: e.g., `Date(2017,12,1)`.

# Example

```jldoctest
julia> using OceanData

julia> soundspeed((-54°, -45°), 100m; date=Date(2017, 12, 1))
1458.7851534823935 m s^-1

julia> soundspeed((-54°, -45°), 10000m; date=Date(2017, 12, 1))
missing

julia> soundspeed((-54°, -45°), 10000m; date=Date(2017, 12, 1), extend=true)
1629.533726798885 m s^-1
```
""" 
function soundspeed((lat, lon), z; date=nothing, extend=false) :: Union{Missing, typeof(1.0m/s)}
    haskey(cache, :soundspeed) && return (cache[:soundspeed]::SST)(lat, lon, z) :: typeof(1.0m/s)

    sal = salinity((lat, lon), z; date, extend)
    temp = temperature((lat, lon), z; date, extend)
    
    (ismissing(sal) || ismissing(temp)) && return missing

    return leroy(sal, temp, z, lat) :: typeof(1.0m/s)
end


"""
    standard_depths

A vector with the dephts reported in the Copernicus database.

I don't recall for which day I got this data, and I haven't checked how different it is
in the other Copernicus databases out there. But, it is something, and it has the expected
feature of being finer-grained at low depths and coarser at greater depths where the profile
variations tend to be smoother.
"""
const standard_depths = parse.(Float64, readlines(joinpath(@__DIR__, "depths.dat"))) .* m


"""
    makeprofile(pfun; zmax=8000m, zs=standard_depths)

Return a profile as a vector of 2-tuples (depth, value) from the function `pfun(z)`.

# Example

```
julia> using OceanData

julia> prof = soundspeed((-45.2°, -54°); date=Date(2017, 12, 1)) |> makeprofile
76-element Vector{Tuple{Quantity{Float64, 𝐋, Unitful.FreeUnits{(m,), 𝐋, nothing}}, Any}}:
 (0.50576 m, 1494.565760656654 m s^-1)
 (1.555855 m, 1494.4249056870487 m s^-1)
 (2.667682 m, 1494.31210736624 m s^-1)
 (3.85628 m, 1494.227685610145 m s^-1)
 (5.140361 m, 1494.1938229984985 m s^-1)
 (6.543034 m, 1494.1891295157416 m s^-1)
 (8.092519 m, 1494.1649669345345 m s^-1)
 (9.82275 m, 1494.1512134131285 m s^-1)
 (11.77368 m, 1494.0624681076447 m s^-1)
 (13.99104 m, 1493.934152456295 m s^-1)
 ⋮
 (4488.155 m, 1525.8759999599588 m s^-1)
 (4687.581 m, 1529.0549497154045 m s^-1)
 (4888.07 m, 1532.4097536968802 m s^-1)
 (5089.479 m, 1535.9092242642012 m s^-1)
 (5291.683 m, 1539.5087758967625 m s^-1)
 (5494.575 m, 1543.170343994254 m s^-1)
 (5698.061 m, 1546.8756085367884 m s^-1)
 (5902.058 m, missing)
 (8000.0 m, missing)

julia> prof[1:3]
3-element Vector{Tuple{Quantity{Float64, 𝐋, Unitful.FreeUnits{(m,), 𝐋, nothing}}, Any}}:
 (0.50576 m, 1494.565760656654 m s^-1)
 (1.555855 m, 1494.4249056870487 m s^-1)
 (2.667682 m, 1494.31210736624 m s^-1)

julia> prof[end]
(8000.0 m, missing)
```
"""
function makeprofile(fun; zmax=8000m, zs=standard_depths)
    zs = push!(filter(z -> z < zmax, zs), zmax)
    
    return [ (z, fun(z)) for z in zs ]
end

"""
    makeprofile(cz::Vector; zmax=nothing, zs=nothing)

This already receives a profile (vector of (z, val) pairs). All it does is 
validate `zmax` and `zs`.

If the keyword arguments are `nothing`, then that check isn't carried out.

I should check why this exists and whether it makes sense for this method to exist at all.
""" # To-do: check this
function makeprofile(cz::Profile; zmax=nothing, zs=nothing)
    !isnothing(zmax) && @assert cz[end][1] ≈ zmax  "Max profile depth $(cz[end][1]) is different from zmax $zmax"
    !isnothing(zs) && @assert isapprox.(first.(cz), zs) "Profile depths are different from the given `zs`"

    return cz
end

"""
    makeprofile(kt; zmax=8000m, zs=standard_depths)

Return a constant profile.

It's equivalent to `makeprofile(z -> kt, zmax, zs)`.
"""
makeprofile(val :: Union{Number, Unitful.Quantity}; kwargs...) = makeprofile(z->val; kwargs...)



"""
    soundspeed(loc; date, extend=false)

Return a function of the depth.

The keyword arguments represent the same as in the full uncurried method.

# Example

```jldoctest
julia> using OceanData

julia> date = Date(2017, 12, 1)
2017-12-01

julia> cz = soundspeed((-45°, -40°); date);

julia> cz(10m)
1490.779038765148 m s^-1
```
"""
soundspeed(loc; date=nothing, extend=false) = z -> soundspeed(loc, z; date, extend)



"""
    salinity(loc; date, extend=false)

Return a function of the depth.

The keyword arguments represent the same as in the full uncurried method.

# Example

```jldoctest
julia> using OceanData

julia> date = Date(2017, 12, 1)
2017-12-01

julia> sz = salinity((-45°, -40°); date);

julia> sz.([10m, 123m])
2-element Vector{Float32}:
 34.5
 34.5
```
"""
salinity(loc; date=nothing, extend=false) = withdate(date) do 
    d = getdate()
    z -> salinity(loc, z; date=d, extend)
end

"""
    temperature(loc; date, extend=false)

Return a function of the depth.

The keyword arguments represent the same as in the full uncurried method.

# Example

```jldoctest
julia> using OceanData

julia> date = Date(2017, 12, 1)
2017-12-01

julia> tz = temperature((-45°, -40°); date);

julia> tz.([10m, 123m])
2-element Vector{Quantity{Float32, 𝚯, Unitful.FreeUnits{(K,), 𝚯, Unitful.Affine{-5463//20}}}}:
 10.391339f0 °C
  8.58506f0 °C
```
"""
temperature(loc; date=nothing, extend=false) = withdate(date) do 
    d = getdate()
    z -> temperature(loc, z; date=d, extend)
end

function withdate(fun, d)

    isnothing(getdate()) && isnothing(d) && setdate(default_date)
    if isnothing(d) # Date not passed as argument
        @info "The data returned applies to date $(getdate())"
    else
        setdate(d)
    end

    return fun()
end


"""
	leroy(salility, temperature, depth, lat)
	leroy(salinity, temperature, depth, (lat, lon))

Return the sound speed according to Leroy's formula.

Temperature and depth must be given in the appropriate units.
The latitude must be in degrees. 
Salinity, when given without units, is assumed to be in per thousand, but when explicitly given with (dimensionless) units (e.g. g/kg, permille), it's assumed as such.

The `(lat, lon)` version is provided for convenience; longitude is irrelevant.

# Example

```jldoctest
julia> using OceanData

julia> OceanData.Copernicus.leroy(34.2, 15°C, 50m, 34°)
1506.6221178062503 m s^-1

julia> OceanData.Copernicus.leroy(34.2, 15°C, 50m, (34°, -48°))
1506.6221178062503 m s^-1
```
"""
function leroy(sal, temp, depth, loc)
	(ismissing(sal) || ismissing(temp)) && return missing

	s = sal isa Real ? sal : ustrip(u"permille", sal)

		# Check validity of latitude format
	latitude = loc isa Tuple ? loc[1] : loc
	Geo.checkgeopos((latitude, latitude))

	lat_u = ustrip(latitude)
	t = ustrip(°C, temp)
	z = ustrip(m, depth)
	res = 1402.5 + 1.33s + 5t - 0.0123s*t - 0.0544*t^2 + 0.000087s*t^2 + 0.00021*t^3 +
	0.0156z + 0.0000143s*z + 3e-7z*t^2 + 2.55e-7*z^2 - 7.3e-12*z^3 - 9.5e-13t*z^3 +
	1.2e-6z*(-45 + abs(lat_u))

	return res * u"m"/u"s"
end


end # module