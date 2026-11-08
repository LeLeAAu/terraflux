using Test,SpeedyWeather,Dates,TOML
include(joinpath(@__DIR__,"..","src","live.jl"));using .TerraFluxLive
using .TerraFluxLive.TerraFluxThermalPatch,.TerraFluxLive.TerraFluxVortexProfiles
include(joinpath(@__DIR__,"..","src","data.jl"));using .TerraFluxData
include(joinpath(@__DIR__,"..","src","thermal_model.jl"));using .TerraFluxThermalModel
include(joinpath(@__DIR__,"..","src","vortex_model.jl"));using .TerraFluxVortexModel
include(joinpath(@__DIR__,"..","src","model_chunk.jl"));using .TerraFluxModelChunk
include(joinpath(@__DIR__,"..","src","session_snapshot.jl"));using .TerraFluxSessionSnapshot
root=isempty(ARGS) ? mktempdir(;cleanup=false) : abspath(ARGS[1]);mkpath(root)
dir=mktempdir(root;prefix="session_",cleanup=false);mkpath(joinpath(dir,"commands"));cd(dir)
truncation=length(ARGS)>2 ? parse(Int,ARGS[3]) : 32
g=SpectralGrid(truncation=truncation,nlayers=8);m=PrimitiveWetModel(g);add!(m,SpeedyWeather.SurfacePressureOutput());s=initialize!(m)
if length(ARGS)>1 && ARGS[2]!="-"
    restore_session_bundle!(s,ARGS[2],dir)
    baseline=abspath(ARGS[2])
else
firstfile=run_chunk!(s,truncation)
baseline=save_session_bundle(s,dir,Dict("truncation"=>truncation,"layers"=>8,"max_chunks"=>8,"chunk_hours"=>6),[firstfile];
    pending_edit=false,undo_file="",undo_previous_pending=false,edit_summary="",sequence=0)
end
println("VORTEX_BASELINE=$baseline");flush(stdout)
@testset "Projected coupled vortex, exact rollback and physical continuation" begin
    before=deepcopy(s.variables.prognostic)
    checkpoint=joinpath(dir,"before.jld2");save_checkpoint(s,checkpoint)
    spec=vortex_spec(lon=130.,lat=truncation>=63 ? 20. : 35.,radius_km=truncation>=63 ? 1700. : 3000.,pressure_drop_hpa=15.)
    effect=apply_vortex!(s,spec)
    @test effect.projected_pressure_min_hpa< -5 && effect.projected_delta_t_max_k>1
    @test effect.air_mass_change_kg<0 && isfinite(effect.dry_enthalpy_change_j)
    @test s.variables.prognostic.humidity==before.humidity
    @test s.variables.prognostic.divergence==before.divergence
    @test s.variables.prognostic.clock.time==before.clock.time
    for name in (:temperature,:pressure,:vorticity)
        d=Array((getproperty(s.variables.prognostic,name)-getproperty(before,name)).data)
        @test maximum(abs,d)>0
        @test selectdim(d,ndims(d),1)≈selectdim(d,ndims(d),2) atol=2e-5
    end
    restore_checkpoint!(s,checkpoint)
    for name in (:temperature,:pressure,:vorticity,:divergence,:humidity)
        @test getproperty(s.variables.prognostic,name)==getproperty(before,name)
    end
    apply_vortex!(s,spec)
    nextfile=run_chunk!(s,truncation);d=load_weather(nextfile)
    @test d.times[end]==DateTime(2000,1,1,12)
    @test all(all(isfinite,a) for a in values(d.fields))
end
println("VORTEX_MODEL_PASSED")
