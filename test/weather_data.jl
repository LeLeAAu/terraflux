using Test,Dates
include(joinpath(@__DIR__,"..","src","data.jl"))
include(joinpath(@__DIR__,"..","src","wind_particles.jl"))
using .TerraFluxData,.TerraFluxWind

@testset "Relative humidity uses actual sigma pressure" begin
    temperature=20f0
    saturation=6.112exp(17.67temperature/(temperature+243.5))
    vapor=saturation/2
    specific=1000*0.622vapor/(1000-0.378vapor)
    fields=Dict{Symbol,Array{Float32}}(:temp=>fill(temperature,2,2,2,1),
        :humid=>fill(Float32(specific),2,2,2,1),:pres=>fill(1000f0,2,2,1),:mslp=>fill(1200f0,2,2,1))
    d=WeatherData("synthetic",[0.,180.],[-30.,30.],[0.5,1.],[DateTime(2000)],fields)
    @test all(isapprox.(frame(d,:rh,2,1),50;atol=1e-4))
    @test all(isapprox.(frame(d,:rh,1,1),25;atol=1e-4))
    fields[:mslp].=800
    @test all(isapprox.(frame(d,:rh,2,1),50;atol=1e-4)) # not sea-level pressure
    fields[:pres].=0
    @test all(isnan,frame(d,:rh,2,1))
    delete!(fields,:pres)
    @test all(isnan,frame(d,:rh,2,1))
    fields[:pres]=fill(1000f0,2,2,1)
    unsupported=WeatherData(d.path,d.lon,d.lat,[500.,1000.],d.times,fields)
    @test all(isnan,frame(unsupported,:rh,2,1))
end

function wind_fixture(;u=10f0,v=0f0)
    lon=collect(-180.:30.:150.);lat=collect(-80.:40.:80.)
    fields=Dict(:u=>fill(u,12,5,1,1),:v=>fill(v,12,5,1,1))
    (lon=lon,lat=lat,fields=fields)
end
@testset "Wind interpolation and spherical particle direction" begin
    d=wind_fixture()
    original=deepcopy(d.fields)
    @test velocity_at(d,1,1,179.,0.)==(10.,0.)
    @test velocity_at(d,1,1,-181.,0.)==(10.,0.)
    @test velocity_at(d,1,1,0.,89.)===nothing
    p=WindParticles(count=1,trail_steps=4,lifetime=1e9,speed=3600)
    p.lon[1]=0;p.lat[1]=0;p.age[1]=0;clear_trails!(p)
    step_particles!(p,d,1,1,0.1)
    @test p.lon[1]≈rad2deg(10*360/6371000) atol=1e-10
    @test p.lat[1]==0
    @test count(q->all(isfinite,q),particle_segments(p))==2
    # Ten m/s is ten m/s, including the cos(latitude) longitude metric.
    p.lon[1]=0;p.lat[1]=60;p.age[1]=0;clear_trails!(p)
    step_particles!(p,d,1,1,0.1)
    @test p.lon[1]≈rad2deg(10*360/(6371000cosd(60))) atol=1e-10
    p.lon[1]=179.99;p.lat[1]=0;p.age[1]=0;clear_trails!(p)
    step_particles!(p,d,1,1,0.1)
    @test p.lon[1]< -179
    @test all(q->!all(isfinite,q),particle_segments(p)) # no dateline chord
    north=wind_fixture(;u=0f0,v=10f0)
    p.lon[1]=0;p.lat[1]=0;p.age[1]=0;clear_trails!(p)
    step_particles!(p,north,1,1,0.1)
    @test p.lat[1]≈rad2deg(10*360/6371000) atol=1e-10
    still=wind_fixture(;u=0f0)
    p.lon[1]=5;p.lat[1]=10;p.age[1]=0;clear_trails!(p)
    step_particles!(p,still,1,1,0.1)
    @test p.lon[1]≈5 && p.lat[1]==10
    holes=wind_fixture();holes.fields[:u].=NaN32
    @test velocity_at(holes,1,1,0.,0.)===nothing
    step_particles!(p,holes,1,1,0.1)
    @test all(q->!all(isfinite,q),particle_segments(p))
    @test all(isequal(d.fields[f],original[f]) for f in keys(original))
    linear=wind_fixture()
    for j in eachindex(linear.lat),i in eachindex(linear.lon)
        linear.fields[:u][i,j,1,1]=linear.lon[i]/10+linear.lat[j]/5
    end
    @test velocity_at(linear,1,1,15.,20.)[1]≈5.5
end
