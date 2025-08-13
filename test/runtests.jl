using OceanData, Test, Documenter

doctest(OceanData)

@testset "OceanData.jl" begin

    date = Date(2017, 12, 1)
    
    @test salinity((-50°, -50°); date)(12m) ≈ 34.03125f0
    @test temperature((-55°, -50°), 555m; date) ≈ 2.6070576f0°C
    @test_throws ArgumentError salinity((-50, -50); date)(12m) ≈ 34.0625
    @test_throws ArgumentError temperature((-55, -50), 555m; date) ≈ 2.5774062°C

    @testset "Standard depths" begin
        @test issorted(diff(standard_depths))
    end

    @testset "Bathymetry" begin
        @test bathymetry((-3°, -15°)) ≈ 3587.250002881934m
        @test ismissing(bathymetry((3°, 15°); nothrow=true))
    end
end
