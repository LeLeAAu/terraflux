include("structure.jl")
@testset "Vortex extent responds to spatial wind size" begin
    function extent(scale)
        d=structured_vortex(;amplitudes=[4.])
        for j in eachindex(d.lat),i in eachindex(d.lon)
            x=6371000cosd(20)*deg2rad(mod(d.lon[i]+180,360)-180)
            y=6371000deg2rad(d.lat[j]-20)
            f=exp(-(x*x+y*y)/(2scale^2))
            d.fields[:u][i,j,:,1].=-5e-5*y*f
            d.fields[:v][i,j,:,1].=5e-5*x*f
        end
        d,model_structure(d,1,(lon=0.,lat=20.))
    end
    narrow,a=extent(300000.)
    broad,b=extent(600000.)
    @test a.radius_km!==nothing && b.radius_km!==nothing
    @test a.radius_km<b.radius_km
    @test !a.radius_censored
    broad.fields[:u].+=100
    @test model_structure(broad,1,(lon=0.,lat=20.)).radius_km===nothing
    scenario=load_scenario(joinpath(@__DIR__,"..","scenarios","demo_storms.toml"))
    @test all(s.radius_km===nothing for system in scenario.systems for s in system.samples)
end
