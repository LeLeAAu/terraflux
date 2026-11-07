using Test
include(joinpath(@__DIR__,"..","src","thermal_patch.jl"))
using .TerraFluxThermalPatch
@testset "Thermal patch geometry and bounds" begin
    s=thermal_spec(lon=179,lat=20,radius_km=2500,layer=8,delta_k=2)
    @test patch_weight(179,20,s)==1
    @test patch_weight(-179,20,s)>0.8
    @test patch_weight(0,-20,s)==0
    @test patch_weight(179,25,s)>patch_weight(179,30,s)>patch_weight(179,40,s)
    @test_throws Exception thermal_spec(;merge(s,(delta_k=0,))...)
    @test_throws Exception thermal_spec(;merge(s,(delta_k=6,))...)
    @test_throws Exception thermal_spec(;merge(s,(radius_km=500,))...)
    @test_throws Exception thermal_spec(;merge(s,(lon=NaN,))...)
    @test_throws Exception thermal_spec(;merge(s,(layer=2.5,))...)
end
