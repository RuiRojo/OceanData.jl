# This build script installs the Copernicus Marine CLI as a Julia artifact
# for the current host platform, and writes `deps/deps.jl` with a constant
# `COPERNICUSMARINE_CLI` pointing to the installed executable.

using Pkg
using Pkg.Artifacts
using Base.BinaryPlatforms
using Downloads

const CLI_VERSION = v"2.2.1"

function pick_url()
    if Sys.islinux()
        # ensure glibc, not musl
        hp = HostPlatform()
        if get(hp.tags, "libc", nothing) == "musl"
            error("Unsupported libc (musl). Please install the Copernicus CLI manually and set ENV[\"COPERNICUSMARINE_CLI\"].")
        end
        txt = try
            readchomp(`ldd --version`)
        catch
            ""
        end
        m = match(r"\d+\.\d+", txt)
        glibc = isnothing(m) ? v"0.0.0" : VersionNumber(m.match)
        if glibc >= v"2.39.0"
            return "https://github.com/mercator-ocean/copernicus-marine-toolbox/releases/download/v$(CLI_VERSION)/copernicusmarine_linux-glibc-2.39.cli"
        else
            return "https://github.com/mercator-ocean/copernicus-marine-toolbox/releases/download/v$(CLI_VERSION)/copernicusmarine_linux-glibc-2.35.cli"
        end
    elseif Sys.isapple()
        return Sys.ARCH === :aarch64 ?
            "https://github.com/mercator-ocean/copernicus-marine-toolbox/releases/download/v$(CLI_VERSION)/copernicusmarine_macos-arm64.cli" :
            "https://github.com/mercator-ocean/copernicus-marine-toolbox/releases/download/v$(CLI_VERSION)/copernicusmarine_macos-x86_64.cli"
    elseif Sys.iswindows()
        return "https://github.com/mercator-ocean/copernicus-marine-toolbox/releases/download/v$(CLI_VERSION)/copernicusmarine_windows-x86_64.exe"
    else
        error("Unsupported platform")
    end
end

function install_cli_artifact()
    # Allow skipping in CI or controlled envs
    if get(ENV, "OCEANDATA_SKIP_CLI_BUILD", "") in ("1", "true", "yes")
        return nothing
    end

    url = pick_url()
    mktempdir() do tmp
        src = joinpath(tmp, basename(url))
        Downloads.download(url, src)

        exe_name = Sys.iswindows() ? "copernicusmarine.exe" : "copernicusmarine"

        art_hash = create_artifact() do artdir
            dest = joinpath(artdir, exe_name)
            cp(src, dest; force=true)
            try
                chmod(dest, 0o755)
            catch
            end
        end

        artifacts_toml = joinpath(@__DIR__, "..", "Artifacts.toml")
        bind_artifact!(artifacts_toml, "copernicusmarine_cli", art_hash;
            platform = HostPlatform(), force = true)

        # Write deps/deps.jl to point at the artifacted executable
        deps_dir = @__DIR__
        isdir(deps_dir) || mkpath(deps_dir)
        open(joinpath(deps_dir, "deps.jl"), "w") do io
            println(io, "using LazyArtifacts")
            println(io, "const COPERNICUSMARINE_CLI = joinpath(artifact\"copernicusmarine_cli\", \"$exe_name\")")
        end
    end

    return nothing
end

install_cli_artifact() 