using Test, Dates
include(joinpath(@__DIR__,"..","src","data.jl"))
using .TerraFluxData
using SpeedyWeather: NCDataset, defDim, defVar

@testset "Independent air, sea and land temperatures" begin
    mktempdir() do dir
        path=joinpath(dir,"surface.nc")
        NCDataset(path,"c") do ds
            for (n,count) in (("lon",2),("lat",2),("layer",2),("soil_layer",2),("time",2))
                defDim(ds,n,count)
            end
            defVar(ds,"lon",[0.,180.],("lon",))
            defVar(ds,"lat",[45.,-45.],("lat",))
            defVar(ds,"layer",[0.25,0.9375],("layer",))
            defVar(ds,"time",[0.,6.],("time",),attrib=Dict("units"=>"hours since 2000-01-01 00:00:00"))
            for (name,value,unit) in (("temp",280f0,"K"),("u",3f0,"m/s"),("v",4f0,"m/s"),("humid",0.01f0,"kg/kg"))
                defVar(ds,name,fill(value,2,2,2,2),("lon","lat","layer","time"),attrib=Dict("units"=>unit))
            end
            defVar(ds,"mslp",fill(1000f0,2,2,2),("lon","lat","time"),attrib=Dict("units"=>"hPa"))
            defVar(ds,"lsm",Float32[0 1;0.5 1],("lon","lat"))
            sst=fill(300f0,2,2,2);sst[:,:,2].+=1
            defVar(ds,"sst",sst,("lon","lat","time"),attrib=Dict("units"=>"K"))
            soil=fill(-10f0,2,2,2,2);soil[:,:,1,:].=35f0
            defVar(ds,"st",soil,("lon","lat","soil_layer","time"),attrib=Dict("units"=>"degC"))
        end
        d=load_weather(path)
        @test all(frame(d,:temp,2,1).≈6.85f0)
        # Sorted cell [2,2] is pure ocean; [2,1] is pure land.
        @test frame(d,:sst,1,1)[2,2]≈26.85f0
        @test isnan(frame(d,:lst,1,1)[2,2])
        @test isnan(frame(d,:sst,1,1)[2,1])
        @test frame(d,:lst,1,1)[2,1]==35f0
        @test isfinite(frame(d,:sst,1,1)[1,2]) && isfinite(frame(d,:lst,1,1)[1,2])
        for f in (:sst,:lst)
            @test isequal(frame(d,f,1,1),frame(d,f,2,1))
            @test isequal(sample_value(d,f,2,1,0.,-45.),frame(d,f,1,1)[2,1])
            @test color_limits(d,f,1,1)==color_limits(d,f,2,1)
        end
        @test color_limits(d,:sst,1,1;locked=true)[2]≈27.85f0
        @test occursin("Không phụ thuộc",field_context(d,:sst,1))
        later=WeatherData(path,d.lon,d.lat,d.layers,d.times.+Hour(6),d.fields)
        joined=append_weather(d,later)
        @test size(joined.fields[:sst])==(2,2,3)
        @test isequal(frame(joined,:lst,2,3),frame(d,:lst,1,2))
        oldfields=Dict(k=>v for (k,v) in d.fields if !(k in (:sst,:lst)))
        older=WeatherData(path,d.lon,d.lat,d.layers,d.times,oldfields)
        extended=append_weather(older,later)
        @test all(isnan,frame(extended,:sst,1,1))
        @test isequal(frame(extended,:sst,2,3),frame(d,:sst,1,2))
        laterold=WeatherData(path,d.lon,d.lat,d.layers,later.times,oldfields)
        @test all(isnan,frame(append_weather(d,laterold),:lst,1,3))
        delete!(d.fields,:sst);delete!(d.fields,:lst)
        @test all(isnan,frame(d,:sst,1,1))
        @test isnan(sample_value(d,:lst,1,1,0.,0.))
        @test color_limits(d,:sst,1,1)==(0f0,1f0)
        NCDataset(path,"a") do ds
            ds["sst"].attrib["units"]="wrong"
        end
        @test_throws ErrorException load_weather(path)
    end
    old=load_weather(joinpath(@__DIR__,"..","run_0001","output.nc"))
    @test all(isnan,frame(old,:sst,8,1))
    @test all(isnan,frame(old,:lst,8,1))
end
