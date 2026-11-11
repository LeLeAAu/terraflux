using Test,Dates,TOML,GLMakie
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer,.TerraFluxViewer.TerraFluxData,.TerraFluxViewer.TerraFluxLive
base=load_weather(joinpath(@__DIR__,"..","run_0001","output.nc"))
v=build_viewer(base;session_root=mktempdir(;cleanup=false));screen=display(v.fig)
function paused()
    latest=Ref{Any}(nothing)
    @assert timedwait(900;pollint=0.05) do
        latest[]=v.poll_live!()
        latest[]!==nothing && latest[]["state"]=="error" && error(latest[]["error"])
        latest[]!==nothing && latest[]["state"]=="paused" && get(latest[],"sequence",0)==v.session[].sequence
    end == :ok
    latest[]
end
try
    @testset "New T63/16-layer session, source switching and saved-session restore" begin
        v.resolutionmenu.i_selected[]=3;v.levelsmenu.i_selected[]=2
        v.durationmenu.i_selected[]=1
        v.newrun.clicks[]+=1
        config=TOML.parsefile(joinpath(v.session[].directory,"config.toml"))
        @test config["truncation"]==63 && config["layers"]==16 && config["backend"]=="cpu"
        @test config["max_chunks"]==40
        paused()
        # Editing next-session settings must not mutate the existing model.
        v.resolutionmenu.i_selected[]=4;v.levelsmenu.i_selected[]=1
        v.newrun.clicks[]+=1
        @test occursin("còn hoạt động",v.livestatus[])
        @test v.active_quality[].truncation==63 && v.active_quality[].layers==16
        v.selected[]=(60,30)
        v.stepmodel.clicks[]+=1;paused()
        @test length(v.history[].layers)==16
        @test size(v.mapvalues[])==(length(v.history[].lon)+1,length(v.history[].lat))
        @test length(v.vertexcolors[])==4length(v.history[].lon)*length(v.history[].lat)
        @test length(v.layermenu.options[])==16
        @test occursin("T63 / 16",v.livestatus[])
        v.layermenu.i_selected[]=16
        v.viewmenu.i_selected[]=2
        @test !isempty(GLMakie.colorbuffer(screen))
        v.sourcemenu.i_selected[]=1
        @test size(v.mapvalues[])==(97,48) && v.layer[]==8
        v.sourcemenu.i_selected[]=2
        @test length(v.layermenu.options[])==16
        v.savesession.clicks[]+=1
        status=paused();saved=status["last_saved"]
        @test isempty(status["command_error"]) && isfile(saved)
        stop_session!(v.session[])
        v.sourcemenu.i_selected[]=1
        v.open_saved!(saved);status=paused()
        @test status["completed"]==1 && isempty(status["command_error"])
        @test v.active_quality[].truncation==63 && length(v.layermenu.options[])==16
        @test v.resolutionmenu.selection[]==85 # Next-session choices are independent.
        v.stepmodel.clicks[]+=1;status=paused()
        @test status["completed"]==2 && length(v.history[].times)==3
        @test v.history[].times[end]-v.history[].times[1]==Hour(12)
        @test !isempty(GLMakie.colorbuffer(screen))
    end
finally
    v.session[]===nothing || stop_session!(v.session[])
    close(screen)
end
