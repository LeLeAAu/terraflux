using Test,Dates,TOML,GLMakie
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer,.TerraFluxViewer.TerraFluxData,.TerraFluxViewer.TerraFluxLive
base=load_weather(joinpath(@__DIR__,"..","run_0001","output.nc"))
v=build_viewer(base);screen=display(v.fig)
function synthetic_grid(nx,ny,nz)
    fields=Dict{Symbol,Array{Float32}}(:temp=>fill(25f0,nx,ny,nz,2),
        :u=>fill(3f0,nx,ny,nz,2),:v=>fill(4f0,nx,ny,nz,2),:humid=>fill(10f0,nx,ny,nz,2),
        :mslp=>fill(1000f0,nx,ny,2),:pres=>fill(1000f0,nx,ny,2))
    WeatherData("synthetic",collect(range(-180.,180.;length=nx+1))[1:end-1],
        collect(range(-89.,89.;length=ny)),collect(range(0.01,0.99;length=nz)),
        [DateTime(2000),DateTime(2000)+Hour(6)],fields)
end
try
    @testset "Quality selection and changing physical grid in one viewer" begin
        @test v.resolutionmenu.selection[]==32
        @test v.levelsmenu.selection[]==8
        @test v.backendmenu.selection[]=="cpu"
        original=copy(v.mapvalues[])
        v.resolutionmenu.i_selected[]=4;v.levelsmenu.i_selected[]=2
        @test v.resolutionmenu.selection[]==85
        @test v.levelsmenu.selection[]==16
        @test isequal(v.mapvalues[],original) # Configuration is only for the next session.
        v.selected[]=(60,30)
        v.fieldmenu.i_selected[]=findfirst(==(:mslp),FIELDS)
        v.nighttoggle.checked[]=true
        for (nx,ny,nz) in ((192,96,16),(256,128,8))
            data=synthetic_grid(nx,ny,nz)
            previous_sigma=v.layer[]==8 && nx==192 ? base.layers[8] : 0.99
            v.replace_data!(data)
            @test v.layer[]==argmin(abs.(data.layers .- previous_sigma))
            @test size(v.mapvalues[])==(nx+1,ny)
            @test length(v.vertexcolors[])==4nx*ny
            @test length(v.layermenu.options[])==nz
            @test length(v.intervention.menu.options[])==nz
            @test v.layer[]<=nz
            @test v.selected[]!==nothing
            @test all(==(1000f0),v.mapvalues[])
            v.layermenu.i_selected[]=nz
            v.fieldmenu.i_selected[]=1
            v.viewmenu.i_selected[]=2
            @test !isempty(GLMakie.colorbuffer(screen))
            v.viewmenu.i_selected[]=1
            @test !isempty(GLMakie.colorbuffer(screen))
            v.fieldmenu.i_selected[]=findfirst(==(:mslp),FIELDS)
        end
        v.replace_data!(base)
        @test size(v.mapvalues[])==(97,48)
        @test v.layer[]<=8
        @test length(v.intervention.menu.options[])==8
        @test !isempty(GLMakie.colorbuffer(screen))
        v.durationmenu.i_selected[]=1
        v.newrun.clicks[]+=1
        @test v.session[]!==nothing && v.history[]===nothing
        cfg=TOML.parsefile(joinpath(v.session[].directory,"config.toml"))
        @test cfg["truncation"]==85 && cfg["layers"]==16
        @test size(v.mapvalues[])==(97,48) # Show the original file until the new run publishes output.
        length(ARGS)>0 && save(first(ARGS),v.fig)
    end
finally
    v.session[]===nothing || stop_session!(v.session[])
    close(screen)
end
