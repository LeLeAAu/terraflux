using Test,Dates
include(joinpath(@__DIR__,"..","src","data.jl"))
using .TerraFluxData
using SpeedyWeather: NCDataset,defDim,defVar

function chunk(path,hours;offset=0f0)
    NCDataset(path,"c") do ds
        for (name,n) in (("lon",4),("lat",2),("layer",2),("time",2));defDim(ds,name,n);end
        defVar(ds,"lon",[0.,90.,180.,270.],("lon",))
        defVar(ds,"lat",[-45.,45.],("lat",))
        defVar(ds,"layer",[0.25,0.75],("layer",))
        defVar(ds,"time",Float64.(hours),("time",),attrib=Dict("units"=>"hours since 2000-01-01 00:00:00"))
        a=reshape(Float32.(1:32),4,2,2,2).+offset
        for (f,unit) in (("temp","degC"),("u","m/s"),("v","m/s"),("humid","kg/kg"))
            defVar(ds,f,f=="humid" ? a.*0.0001f0 : a,("lon","lat","layer","time"),attrib=Dict("units"=>unit))
        end
        for f in ("mslp","pres")
            defVar(ds,f,fill(1013f0+offset,4,2,2),("lon","lat","time"),attrib=Dict("units"=>"hPa"))
        end
    end
end

@testset "Archived history preserves time, units and pre-edit frames" begin
    mktempdir() do root
        a,b,c=(joinpath(root,"$n.nc") for n in ("a","b","c"))
        chunk(a,[0,6]);chunk(b,[6,12];offset=10f0)
        joined=load_live_history([a,b])
        expected=append_weather(load_live_chunk(a;initial=true),load_live_chunk(b))
        @test joined.times==expected.times==[DateTime(2000)+Hour(h) for h in (0,6,12)]
        @test all(isequal(joined.fields[f],expected.fields[f]) for f in keys(expected.fields))
        @test all(isnan,frame(joined,:mslp,1,1)) && all(isnan,frame(joined,:pres,1,1))
        @test frame(joined,:temp,2,2)==frame(load_weather(a),:temp,2,2)
        @test frame(joined,:temp,2,3)==frame(load_weather(b),:temp,2,2)
        chunk(c,[12,18]);@test_throws ErrorException load_live_history([a,c])
        chunk(c,[6,9]);@test_throws ErrorException load_live_history([a,c])
        @test_throws ErrorException load_live_history(String[])
        chunk(c,[6,6]);@test_throws ErrorException load_weather(c)
    end
end
