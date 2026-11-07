using Test,Dates
include(joinpath(@__DIR__,"..","src","globe.jl"))
include(joinpath(@__DIR__,"..","src","map_math.jl"))
include(joinpath(@__DIR__,"..","src","experiment_config.jl"))
using .TerraFluxGlobe,.TerraFluxMapMath,.TerraFluxExperimentConfig
@testset "Globe interpolation, geodesic lines and solar time" begin
    xs=[-180.,-90.,0.,90.];ys=[-45.,45.]
    g=smooth_globe_geometry(xs,ys;factor=2)
    @test all(p->sum(abs2,p)≈1,g.points)
    @test all(f->all(i->1<=i<=length(g.points),f),g.faces)
    @test all(==(5f0),smooth_globe_colors(fill(5f0,4,2),g))
    field=Float32[x+2y for x in xs,y in ys]
    v=smooth_globe_colors(field,g)
    i=findfirst(p->abs(p[1]-cosd(-45))<1e-8 && abs(p[2]-sind(-45))<1e-8 && abs(p[3])<1e-8,g.points)
    @test v[i]≈-45
    @test v[1]==v[9] # shared pole
    @test v[19]==v[27] # periodic seam at the equator
    @test all(isnan,smooth_globe_colors(fill(NaN32,4,2),g))
    line=smooth_sphere_lines([(0.,0.),(30.,0.),(NaN,NaN),(179.,45.),(-179.,45.)])
    @test length(line)>60
    @test all(p->!all(isfinite,p) || isapprox(sqrt(sum(abs2,p)),1.004),line)
    for k in 1:length(line)-1
        a,b=line[k],line[k+1]
        all(isfinite,a) && all(isfinite,b) || continue
        middle=ntuple(i->(a[i]+b[i])/2,3)
        @test sqrt(sum(abs2,middle))>1 # dense chords cannot cut into the globe
    end
    noon=solar_direction(DateTime(2000,3,20,12))
    midnight=solar_direction(DateTime(2000,3,20,0))
    @test sum(abs2,noon)≈1
    @test night_strength(0,0,noon)==0 && night_strength(180,0,noon)==1
    @test night_strength(0,0,midnight)==1
    @test solar_direction(DateTime(2000,6,21,12))[3]>0.38
    @test solar_direction(DateTime(2000,12,21,12))[3]< -0.38
    boundary=radius_outline(179,20,800)
    for p in boundary
        a=sind((p[2]-20)/2)^2+cosd(20)*cosd(p[2])*sind((p[1]-179)/2)^2
        @test 2*6371asin(sqrt(a))≈800 atol=1e-8
    end
end
@testset "Local experiment configuration and estimates" begin
    c=experiment_config(days=1,truncation=63,layers=16,output_hours=3)
    @test estimate_experiment(c).frames==9
    @test estimate_experiment(experiment_config(truncation=63)).disk_mib>estimate_experiment(experiment_config()).disk_mib
    @test_throws Exception experiment_config(days=0)
    @test_throws Exception experiment_config(days=1.5)
    @test_throws Exception experiment_config(truncation=999)
    @test_throws Exception experiment_config(output_hours=5)
end
