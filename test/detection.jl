using Test,Dates
include(joinpath(@__DIR__,"..","src","storms.jl"))
include(joinpath(@__DIR__,"..","src","detection.jl"))
using .TerraFluxStorms,.TerraFluxDetection

function vortex_data(; centers=[(0.,20.),(5.,20.),(10.,20.)], sign=1., hours=6, depth=20.)
    lon=collect(-180.:5.:175.)
    lat=collect(-80.:5.:80.)
    nx,ny,nt=length(lon),length(lat),length(centers)
    p=fill(1010f0,nx,ny,nt)
    u=zeros(Float32,nx,ny,1,nt);v=similar(u)
    for (t,center) in enumerate(centers),j in 1:ny,i in 1:nx
        x=6371000*cosd(center[2])*deg2rad(mod(lon[i]-center[1]+180,360)-180)
        y=6371000*deg2rad(lat[j]-center[2])
        factor=exp(-(x*x+y*y)/(2*900000.0^2))
        p[i,j,t]-=depth*factor
        u[i,j,1,t]=-sign*5e-5*y*factor
        v[i,j,1,t]=sign*5e-5*x*factor
    end
    (path="synthetic-vortex",lon=lon,lat=lat,layers=[0.9375],times=[DateTime(2000)+Hour(hours*(t-1)) for t in 1:nt],fields=Dict(:mslp=>p,:u=>u,:v=>v))
end
@testset "Physical candidate detection and past-only identity" begin
    d=vortex_data()
    before=deepcopy(d.fields)
    detected=detect_tracks(d)
    @test length(detected.systems)==1
    @test detected.provenance=="model_detection"
    track=only(detected.systems)
    @test track.id=="MODEL-0001"
    @test getfield.(track.samples,:lon)==[0.,5.,10.]
    @test all(s -> s.kind=="model_low",track.samples)
    @test all(s -> storm_class(s.kind,s.wind_knots)==:MODEL_LOW,track.samples)
    @test storm_state(track,d.times[1]+Hour(3)) === nothing # no inferred intermediate model state
    @test storm_state(track,d.times[2]).lon==5
    @test detected.sigma==0.9375
    @test detected.metrics[(track.id,d.times[1])].pressure_depth_hpa>=2
    @test detected.metrics[(track.id,d.times[1])].vorticity_s>=1e-5
    @test track.samples[1].pressure_hpa==minimum(d.fields[:mslp][:,:,1])
    @test all(d.fields[f]==before[f] for f in keys(before))
    # Analytic solid-body rotation on a sphere: zeta = 2 Omega sin(latitude).
    omega=1e-5
    u=[6371000omega*cosd(phi) for x in d.lon,phi in d.lat]
    zeta=spherical_vorticity(u,zeros(size(u)),d.lon,d.lat)
    @test zeta[37,21] ≈ 2omega*sind(d.lat[21]) rtol=0.01
    south=detect_tracks(vortex_data(;centers=[(0.,-20.),(5.,-20.)],sign=-1))
    @test length(south.systems)==1
    @test first(values(south.metrics)).vorticity_s<0
    @test isempty(detect_tracks(vortex_data(;sign=-1)).systems) # anticyclonic winds rejected
    @test isempty(detect_tracks(vortex_data(;depth=0.)).systems) # rotation without low pressure rejected
    @test isempty(detect_tracks(vortex_data(;centers=[(0.,0.),(5.,0.)])).systems)
    missing=vortex_data()
    missing.fields[:mslp][:,:,2].=NaN32
    gaps=detect_tracks(missing)
    @test length(gaps.systems)==2
    @test !gaps.systems[1].samples[end].active
    @test storm_state(gaps.systems[1],missing.times[2])===nothing
    @test gaps.systems[2].id=="MODEL-0002"
    largegap=detect_tracks(vortex_data(;centers=[(0.,20.),(0.,20.)],hours=24))
    @test length(largegap.systems)==2
    fast=detect_tracks(vortex_data(;centers=[(0.,20.),(80.,20.)]))
    @test length(fast.systems)==2
    seam=detect_tracks(vortex_data(;centers=[(175.,20.),(-180.,20.),(-175.,20.)]))
    @test length(seam.systems)==1
    @test great_circle_km(179,20,-179,20)<220
    @test all(abs(s.a[1]-s.b[1])<=180 for s in history_segments(only(seam.systems),d.times[end]))
    # Adding later records cannot revise the IDs/observations of earlier records.
    prefix=vortex_data(;centers=[(0.,20.),(5.,20.)])
    earlier=detect_tracks(prefix)
    @test earlier.systems[1].samples==track.samples[1:2]
    @test storm_class("model_low",200)==:MODEL_LOW
    a=vortex_data(;centers=[(-40.,20.),(-35.,20.)])
    b=vortex_data(;centers=[(40.,20.),(45.,20.)])
    combined=merge(a,(fields=Dict(:mslp=>a.fields[:mslp]+b.fields[:mslp].-1010f0,:u=>a.fields[:u]+b.fields[:u],:v=>a.fields[:v]+b.fields[:v]),))
    two=detect_tracks(combined)
    @test length(two.systems)==2
    @test all(length(s.samples)==2 for s in two.systems)
    capped=detect_tracks(combined;config=DetectionConfig(max_candidates=1))
    @test all(r.capped && r.kept==1 && r.found==2 for r in capped.reports)
    unknown=vortex_data(); unknown.fields[:mslp].=NaN32
    missing_pressure=detect_tracks(unknown)
    @test isempty(missing_pressure.systems)
    @test all(r.valid_pressure==0 for r in missing_pressure.reports)
    missing_wind=vortex_data(); missing_wind.fields[:u].=NaN32
    wind_result=detect_tracks(missing_wind)
    @test isempty(wind_result.systems)
    @test all(r.valid_wind==0 for r in wind_result.reports)
    @test_throws ErrorException detect_tracks(merge(d,(lon=d.lon[2:end-1],)))
    @test_throws ErrorException detect_tracks(d;config=DetectionConfig(max_speed_mps=Inf))
end
