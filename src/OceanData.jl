module OceanData

export bathymetry

include("Copernicus.jl")
using .Copernicus
using Dates: Date
using Unitful: m, s, °, °C, km,yd
using Reexport
@reexport using Geo

export Date
export temperature, salinity, soundspeed, refraction_index
export makeprofile
export Copernicus
export standard_depths
export m, s, °, °C, km, yd
export bathymetry


const DEF = (;
	c0 = 1500m/s
)

function bathymetry(xs...; nothrow=false, kwargs...)
	out = -elevation(xs...; kwargs...)
	out < 0m && begin
		nothrow && return missing
		throw("You can't request the bathymetry on land (bathymetry on $xs returned $out).")
	end

	return out
end

"""
Use similarly to soundspeed but with extra kwarg c0 with reference sound speed, defaulting to 1500m/s
"""
refraction_index(c::Unitful.Velocity; c0=DEF.c0) = upreferred.(c0 ./ c )
refraction_index(loc, z; c0=DEF.c0, kwargs...) = refraction_index( soundspeed(loc, z; kwargs...); c0)
refraction_index(loc; c0=DEF.c0, kwargs...) = let cz = soundspeed(loc; kwargs...)
	return z -> upreferred(c0 / cz(z))
end

end
