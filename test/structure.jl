using Test,Dates
include(joinpath(@__DIR__,"..","src","storms.jl"))
include(joinpath(@__DIR__,"..","src","detection.jl"))
using .TerraFluxStorms,.TerraFluxDetection

function structured_vortex(;amplitudes=[4.,-4.,0.],latitude=20.,longitude=0.,spacing=2.5,
        sigmas=[0.3,0.5,0.7,0.9375],upper_sign=1.)
    lon=collect(-180.:spacing:180-spacing);lat=collect(-80.:spacing:80.)
    nx,ny,nz,nt=length(lon),length(lat),length(sigmas),length(amplitudes)
    pressure=fill(1010f0,nx,ny,nt)
    u=zeros(Float32,nx,ny,nz,nt);v=similar(u);temp=similar(u)
    for t in 1:nt,j in 1:ny,i in 1:nx
        dx=deg2rad(mod(lon[i]-longitude+180,360)-180)
        x=6371000cosd(latitude)*dx;y=6371000deg2rad(lat[j]-latitude)
        wide=exp(-(x*x+y*y)/(2*900000.0^2))
        # Known, localized temperature perturbation on a sloping background.
        local_core=exp(-(x*x+y*y)/(2*350000.0^2))
        pressure[i,j,t]-=20wide
        for k in 1:nz
            u[i,j,k,t]=-sign(latitude)*5e-5*y*wide
            v[i,j,k,t]=sign(latitude)*5e-5*x*wide
            temp[i,j,k,t]=25sigmas[k]-0.7lat[j]+0.2x/1000000+
                amplitudes[t]*local_core*(sigmas[k]<0.4 ? upper_sign : 1)
        end
    end
    (path="known-thermal-vortex",lon=lon,lat=lat,layers=sigmas,
        times=[DateTime(2000)+Hour(6(t-1)) for t in 1:nt],
        fields=Dict(:mslp=>pressure,:u=>u,:v=>v,:temp=>temp))
end

@testset "Thermal structure and quadrant wind evidence" begin
    d=structured_vortex()
    original=deepcopy(d.fields)
    r=detect_tracks(d)
    @test length(r.systems)==1
    system=only(r.systems)
    @test getfield.(system.samples,:kind)==["model_warm","model_cold","model_low"]
    m=[r.metrics[(system.id,t)] for t in d.times]
    @test getfield.(m,:thermal_core)==[:warm,:cold,:mixed]
    @test m[1].lower_anomaly_k>0.5 && m[1].upper_anomaly_k>0.5
    @test m[2].lower_anomaly_k < -0.5 && m[2].upper_anomaly_k < -0.5
    @test abs(m[3].lower_anomaly_k)<1e-5 && abs(m[3].upper_anomaly_k)<1e-5 # remove background gradient
    @test all(x->x.circulation==:supported,m)
    @test all(v->v>2,m[1].quadrant_wind_mps)
    @test m[1].lower_sigmas==[0.5,0.7] && m[1].upper_sigmas==[0.3]
    @test storm_state(system,d.times[1]+Hour(3))===nothing # no model interpolation after kind changes
    @test getfield.(history_segments(system,d.times[3]),:category)==[:MODEL_WARM,:MODEL_COLD]
    for kind in ("model_warm","model_cold")
        classification=classify_system(kind,200;wind_average_minutes=1,wind_height_m=10,basin=:wpac)
        @test classification.sshws===nothing && !classification.super_typhoon
    end
    @test all(isequal(d.fields[f],original[f]) for f in keys(original))
    south=structured_vortex(;latitude=-20.,amplitudes=[4.])
    southern=model_structure(south,1,(lon=0.,lat=-20.))
    @test southern.thermal_core==:warm && southern.circulation==:supported
    seam=structured_vortex(;longitude=175.,amplitudes=[4.])
    seam_result=model_structure(seam,1,(lon=175.,lat=20.))
    @test seam_result.thermal_core==:warm && seam_result.circulation==:supported
    mixed=structured_vortex(;upper_sign=-1.,amplitudes=[4.])
    @test model_structure(mixed,1,(lon=0.,lat=20.)).thermal_core==:mixed
    no_heat=structured_vortex(;amplitudes=[0.])
    @test model_structure(no_heat,1,(lon=0.,lat=20.)).thermal_core==:mixed
    one_band=structured_vortex(;sigmas=[0.5,0.7,0.9375],amplitudes=[4.])
    absent=model_structure(one_band,1,(lon=0.,lat=20.))
    @test absent.thermal_core==:unknown && absent.upper_anomaly_k===nothing
    no_temperature=structured_vortex(;amplitudes=[4.]);delete!(no_temperature.fields,:temp)
    absent=model_structure(no_temperature,1,(lon=0.,lat=20.))
    @test absent.thermal_core==:unknown && occursin("Thiếu trường",absent.thermal_reason)
    missing=structured_vortex(;amplitudes=[4.]);missing.fields[:temp].=NaN32
    absent=model_structure(missing,1,(lon=0.,lat=20.))
    @test absent.thermal_core==:unknown && absent.lower_anomaly_k===nothing
    wind_missing=structured_vortex(;amplitudes=[4.]);wind_missing.fields[:u].=NaN32
    absent=model_structure(wind_missing,1,(lon=0.,lat=20.))
    @test absent.circulation==:unknown && all(isnothing,absent.quadrant_wind_mps)
    open_flow=structured_vortex(;amplitudes=[4.]);open_flow.fields[:u].+=100
    @test model_structure(open_flow,1,(lon=0.,lat=20.)).circulation==:not_supported
    coarse=structured_vortex(;spacing=10.,amplitudes=[4.])
    @test model_structure(coarse,1,(lon=0.,lat=20.)).thermal_core==:unknown
    prefix=structured_vortex(;amplitudes=[4.,-4.])
    earlier=detect_tracks(prefix)
    @test earlier.systems[1].samples==system.samples[1:2]
    @test all(earlier.metrics[key]==r.metrics[key] for key in keys(earlier.metrics))
end
