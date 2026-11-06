using Test, Dates
include(joinpath(@__DIR__, "..", "src", "data.jl"))
using .TerraFluxData
using SpeedyWeather: NCDataset, defDim, defVar

function fixture(path)
    NCDataset(path, "c") do ds
        for (n, count) in (("lon",4), ("lat",2), ("layer",2), ("time",2))
            defDim(ds, n, count)
        end
        defVar(ds,"lon",[0.,90.,180.,270.],("lon",))
        defVar(ds,"lat",[45.,-45.],("lat",))
        defVar(ds,"layer",[0.25,0.75],("layer",))
        defVar(ds,"time",[0.,6.],("time",),attrib=Dict("units"=>"hours since 2000-01-01 00:00:00"))
        a = reshape(Float32.(1:32),4,2,2,2)
        for (n, values, unit) in (("temp",a .+ 273.15f0,"K"), ("u",fill(3f0,4,2,2,2),"m/s"),
            ("v",fill(4f0,4,2,2,2),"m/s"), ("humid",fill(0.01f0,4,2,2,2),"kg/kg"))
            defVar(ds,n,values,("lon","lat","layer","time"),attrib=Dict("units"=>unit))
        end
        defVar(ds,"mslp",fill(101325f0,4,2,2),("lon","lat","time"),attrib=Dict("units"=>"Pa"))
    end
end

@testset "Data ordering, units, selection and scale" begin
    mktempdir() do dir
        path = joinpath(dir,"fixture.nc")
        fixture(path)
        d = load_weather(path)
        @test d.lon == [-180.,-90.,0.,90.]
        @test d.lat == [-45.,45.]
        @test d.times == [DateTime(2000), DateTime(2000)+Hour(6)]
        original = reshape(Float32.(1:32),4,2,2,2)
        @test frame(d,:temp,2,2) ≈ original[[3,4,1,2],[2,1],2,2] atol=2e-5
        @test all(frame(d,:wind,1,1) .== 5)
        @test all(frame(d,:humid,1,1) .== 10)
        @test all(frame(d,:mslp,2,2) .== 1013.25f0)
        @test frame(d,:mslp,1,2) == frame(d,:mslp,2,2)
        @test nearest_cell(d,181,44) == (1,2)
        @test nearest_cell(d,-179,-90) == (1,1)
        @test sample_value(d,:temp,2,2,181,44) ≈ original[3,1,2,2] atol=2e-5
        @test color_limits(d,:temp,1,1) == color_limits(d,:temp,1,2)
        @test color_limits(d,:temp,1,1; locked=false) != color_limits(d,:temp,1,2; locked=false)
        @test color_limits(d,:u,1,1) == (-3f0,3f0)
        @test color_limits(d,:humid,1,1)[1] < color_limits(d,:humid,1,1)[2]
        @test_throws BoundsError frame(d,:temp,3,1)
        @test_throws Exception load_weather(joinpath(dir,"absent.nc"))
        NCDataset(path,"a") do ds
            ds["temp"].attrib["units"] = "unexpected"
        end
        @test_throws ErrorException load_weather(path)
    end
end

@testset "Repository output matches raw NetCDF" begin
    path = joinpath(@__DIR__,"..","run_0001","output.nc")
    d = load_weather(path)
    @test size(frame(d,:temp,8,41)) == (96,48)
    @test length(d.times) == 41
    @test d.times[end] - d.times[1] == Day(10)
    NCDataset(path) do ds
        @test frame(d,:temp,8,41)[1,1] == ds["temp"][49,48,8,41]
        @test frame(d,:humid,8,41)[1,1] == 1000f0*ds["humid"][49,48,8,41]
        @test frame(d,:mslp,8,41)[1,1] == ds["mslp"][49,48,41]
        @test frame(d,:wind,8,41)[1,1] ≈ hypot(ds["u"][49,48,8,41],ds["v"][49,48,8,41])
    end
end
