using Test,Dates
include(joinpath(@__DIR__,"..","src","data.jl"));using .TerraFluxData
@testset "Streaming scales and scalar samples match full frames" begin
    times=[DateTime(2000)+Hour(6i) for i in 0:2]
    fields=Dict(:temp=>reshape(Float32.(1:48),4,2,2,3),:u=>fill(3f0,4,2,2,3),
        :v=>fill(4f0,4,2,2,3),:humid=>fill(10f0,4,2,2,3),
        :mslp=>fill(1010f0,4,2,3),:pres=>fill(1000f0,4,2,3))
    fields[:u][2,1,1,3]=-30f0;fields[:temp][3,2,1,2]=NaN32;fields[:pres][:,:,1].=NaN32
    d=WeatherData("fixture",[-180.,-90.,0.,90.],[-45.,45.],[0.5,1.],times,fields)
    for f in FIELDS,k in 1:2
        frames=[frame(d,f,k,t) for t in eachindex(times)]
        finite=filter(isfinite,vec(cat(frames...;dims=3)))
        lo,hi=isempty(finite) ? (0f0,1f0) : extrema(finite)
        expected=f in (:u,:v) ? (-max(abs(lo),abs(hi),1f-3),max(abs(lo),abs(hi),1f-3)) : isempty(finite) ? (0f0,1f0) : lo==hi ? (lo-.5f0,hi+.5f0) : (lo,hi)
        @test color_limits(d,f,k,1)==expected
        for t in 1:3,(i,j) in ((1,1),(3,2))
            @test isequal(sample_value(d,f,k,t,d.lon[i],d.lat[j]),frames[t][i,j])
        end
    end
    @test nearest_cell(d,181,90)==(1,2)
    @test finite_extrema(fill(NaN32,2,2))===nothing
    @test finite_extrema(Float32[NaN,Inf,-Inf,2,-3])==(-3f0,2f0)
    @test finite_extrema((x for x in Float32[NaN,Inf,-Inf,2,-3]))==(-3f0,2f0)
    fields[:u].=NaN32;@test color_limits(d,:u,1,1)==(0f0,1f0)
    delete!(fields,:pres);@test color_limits(d,:rh,1,1)==(0f0,1f0)
    changed=copy(fields);delete!(changed,:humid)
    other=WeatherData(d.path,d.lon,d.lat,d.layers,d.times .+ Hour(12),changed)
    @test_throws ErrorException append_weather(d,other)
end
