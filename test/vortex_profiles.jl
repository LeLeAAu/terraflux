using Test
include(joinpath(@__DIR__,"..","src","vortex_profiles.jl"));using .TerraFluxVortexProfiles
@testset "Reference vortex physics and spherical directions" begin
    s=vortex_spec(lon=179.,lat=30.,radius_km=2500.,pressure_drop_hpa=15.)
    for r in (0.,1.,2e5,8e5,2e6,2.5e6),sigma in (1.,0.9,0.5,0.1)
        a=vortex_column(r,sigma,s)
        @test all(isfinite,values(a)) && a.delta_tv>=0
        @test a.y-(-a.delta_logps)*(-expm1(-s.depth*a.y))≈-log(sigma) atol=1e-11
        if 0<r<2.5e6
            f=2*7.29e-5*sind(s.lat)
            @test a.u_theta^2/r+f*a.u_theta≈a.acceleration rtol=1e-12
        end
    end
    # Hydrostatic pressure law of the reference isothermal atmosphere.
    A=-log1p(-15/1000);w=(1-0.2)^4*(1+4*0.2);y=0.4;h=1e-5;k=s.depth
    lnp(z)=-z-A*w*exp(-k*z)
    expected=300/(1-A*w*k*exp(-k*y))
    @test -300/((lnp(y+h)-lnp(y-h))/(2h))≈expected rtol=1e-9
    north=vortex_at(179.,32.,1.,s);east=vortex_at(-179.,30.,1.,s)
    @test north.u<0 && east.v>0
    sh=vortex_spec(lon=179.,lat=-30.,radius_km=2500.,pressure_drop_hpa=15.)
    @test vortex_at(-179.,-30.,1.,sh).v<0
    @test vortex_at(179.,30.,1.,s).u==0
    @test vortex_column(3e6,0.9,s).delta_logps==0
    @test reference_profile(s).max_wind_mps>0
    for expanded in ((lat=5.,radius_km=100.,),(lat=65.,radius_km=5000.,),(pressure_drop_hpa=150.,),(pressure_drop_hpa=1.,depth=10.,),(depth=0.,))
        e=vortex_spec(;merge(s,expanded)...)
        @test all(isfinite,values(reference_profile(e)))
        @test vortex_column(0.,1.,e).delta_tv>=0
    end
    for bad in ((lat=0.,),(lat=91.,),(radius_km=0.,),(pressure_drop_hpa=0.,),
            (pressure_drop_hpa=1000.,),(pressure_drop_hpa=500.,depth=2.,),(depth=-1.,),
            (depth=Inf,),(pressure_drop_hpa=true,),(lat=10.,radius_km=2500.))
        @test_throws ErrorException vortex_spec(;merge(s,bad)...)
    end
end
