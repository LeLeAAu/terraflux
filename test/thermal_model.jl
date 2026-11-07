using Test,SpeedyWeather,Dates,Random
include(joinpath(@__DIR__,"..","src","thermal_patch.jl"))
include(joinpath(@__DIR__,"..","src","thermal_model.jl"))
using .TerraFluxThermalPatch,.TerraFluxThermalModel
@testset "Real spectral thermal perturbation and checkpoint restore" begin
    g=SpectralGrid(truncation=21,nlayers=8);m=PrimitiveWetModel(g);s=initialize!(m)
    run!(s;period=Hour(6),output=false)
    before=deepcopy(s.variables)
    p=thermal_spec(lon=130,lat=20,radius_km=3000,layer=8,delta_k=2)
    mktempdir() do dir
        next_random=rand(copy(Random.default_rng()))
        file=joinpath(dir,"before.jld2");save_checkpoint(s,file)
        @test rand(copy(Random.default_rng()))==next_random
        effect=apply_thermal!(s,p)
        @test s.variables.prognostic.clock.time==before.prognostic.clock.time
        @test effect.heat_dry_approx_j>0 && effect.global_layer_mean_delta_k>0
        @test 0<effect.projected_max_k<2.5 && effect.native_cells>=4
        @test s.variables.prognostic.humidity==before.prognostic.humidity
        @test s.variables.prognostic.vorticity==before.prognostic.vorticity
        delta=Array((s.variables.prognostic.temperature-before.prognostic.temperature).data)
        @test maximum(abs,delta[:,1:7,:])==0
        @test delta[:,8,1]≈delta[:,8,2] atol=1e-5
        restore_checkpoint!(s,file)
        for name in (:temperature,:humidity,:vorticity,:divergence,:pressure)
            @test getproperty(s.variables.prognostic,name)==getproperty(before.prognostic,name)
        end
        @test s.variables.prognostic.clock.time==before.prognostic.clock.time
        @test rand(copy(Random.default_rng()))==next_random
    end
end
