using Test,Dates,TOML
include(joinpath(@__DIR__,"..","src","data.jl"));using .TerraFluxData
include(joinpath(@__DIR__,"..","src","live.jl"));using .TerraFluxLive
include(joinpath(@__DIR__,"..","src","comparison.jl"));using .TerraFluxComparison
@testset "A/B derived fields, missing values and time selection" begin
    function data(T,u,v,q)
        fields=Dict(:temp=>fill(T,2,2,1,2),:u=>fill(u,2,2,1,2),:v=>fill(v,2,2,1,2),
            :humid=>fill(q,2,2,1,2),:mslp=>fill(1013f0,2,2,2),:pres=>fill(1000f0,2,2,2))
        WeatherData("fixture",[-180.,0.],[-45.,45.],[1.],[DateTime(2000),DateTime(2000)+Hour(6)],fields)
    end
    a=data(25f0,3f0,4f0,10f0);b=data(27f0,-3f0,-4f0,12f0)
    r=(;a,b,times=a.times[2:end])
    @test all(comparison_values(r,:temp,1,1).delta.==2)
    @test all(comparison_values(r,:wind,1,1).delta.==0) # Difference of speeds, not speed of vector difference.
    rh=comparison_values(r,:rh,1,1)
    @test rh.delta≈frame(b,:rh,1,2).-frame(a,:rh,1,2)
    a.fields[:temp][1,1,1,2]=NaN32
    @test isnan(comparison_values(r,:temp,1,1).delta[1,1])
    @test_throws BoundsError comparison_values(r,:temp,1,2)
    @test_throws BoundsError comparison_values(r,:temp,2,1)
    mktempdir() do root
        m=Dict{String,Any}("format"=>"terraflux.comparison","format_version"=>1,"steps"=>1,
            "fork_time"=>"2000-01-01T06:00:00","state"=>"running","outputs_a"=>Any[],"outputs_b"=>Any[])
        file=joinpath(root,"comparison.toml")
        put(x)=open(io->TOML.print(io,x),file,"w")
        put(m);@test_throws ErrorException load_comparison(file)
        m["state"]="complete";put(m);@test_throws ErrorException comparison_manifest(file)
        m["state"]="running";m["outputs_a"]=[Dict("path"=>"../outside.nc")]
        put(m);@test_throws ErrorException comparison_manifest(file)
    end
    @test_throws ErrorException start_comparison("missing";steps=0)
end
