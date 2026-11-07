# End-to-end GUI test with a real worker, display and OpenGL required.
using GLMakie, Test, Dates, TOML
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer
using .TerraFluxViewer.TerraFluxData
using .TerraFluxViewer.TerraFluxLive
using .TerraFluxViewer.TerraFluxDetection
path = get(ENV,"TERRAFLUX_TEST_DATA",joinpath(@__DIR__,"..","run_0001","output.nc"))
data = load_weather(path)
surface=length(data.layers)
root = mktempdir(;prefix="terraflux gui test ")
viewer = build_viewer(data;session_root=root)
screen = display(viewer.fig)
function await_gui(predicate;timeout=600)
    result = timedwait(timeout;pollint=0.05) do
        status = viewer.poll_live!()
        viewer.tracker.poll_model!()
        status !== nothing && status["state"] == "error" && error(status["error"])
        predicate(status)
    end
    result == :ok || error("GUI simulation timed out: $(viewer.livestatus[])")
end
try
    @testset "Live GUI with a real simulation process" begin
        viewer.runmodel.clicks[] += 1
        @test occursin("Phiên mới",viewer.livestatus[])
        viewer.newrun.clicks[] += 1
        @test viewer.session[] !== nothing
        @test viewer.durationmenu.selection[]==60
        @test TOML.parsefile(joinpath(viewer.session[].directory,"config.toml"))["max_chunks"]==240
        cfg=TOML.parsefile(joinpath(viewer.session[].directory,"config.toml"))
        @test cfg["layers"]==surface
        expected_T=TerraFluxData.NCDataset(path,"r") do ds;Int(get(ds.attrib,"terraflux_truncation",32));end
        @test cfg["truncation"]==expected_T
        await_gui(s -> s !== nothing && s["state"] == "paused")
        viewer.selected[] = (60,30)
        viewer.stepmodel.clicks[] += 1
        await_gui(s -> s["state"] == "paused" && s["completed"] == 1)
        @test viewer.history[] !== nothing
        @test length(viewer.history[].times) == 2
        @test haskey(viewer.history[].fields,:pres)
        @test all(isnan,frame(viewer.history[],:rh,surface,1))
        @test viewer.time[] == 2
        @test viewer.slider.range[] == 1:2
        @test viewer.selected[] == (60,30)
        @test viewer.mapvalues[][1:end-1,:] == frame(viewer.history[],:temp,surface,2)
        viewer.viewmenu.i_selected[]=3
        viewer.tracker.source_menu.i_selected[]=2
        await_gui(s -> viewer.tracker.catalog[] isa ModelStormSet)
        model=viewer.tracker.catalog[]
        @test model.source_path==viewer.history[].path
        @test length(model.reports)==2
        @test model.reports[1].valid_pressure==0
        @test model.reports[1].kept==0
        @test model.reports[2].valid_pressure>0
        viewer.tracker.source_menu.i_selected[]=1
        viewer.sourcemenu.i_selected[] = 1
        @test viewer.mapvalues[][1:end-1,:] == frame(data,:temp,surface,length(data.times))
        @test viewer.slider.range[] == 1:length(data.times)
        viewer.sourcemenu.i_selected[] = 2
        @test viewer.slider.range[] == 1:2
        viewer.fieldmenu.i_selected[] = 6  # MSLP
        set_close_to!(viewer.slider,1)
        @test all(isnan,viewer.mapvalues[])
        set_close_to!(viewer.slider,2)
        @test all(isfinite,viewer.mapvalues[])
        viewer.fieldmenu.i_selected[] = 1
        viewer.viewmenu.i_selected[] = 2
        viewer.pausemodel.clicks[] += 1
        await_gui(s -> s["state"] == "paused" && s["sequence"] == viewer.session[].sequence)
        viewer.stepmodel.clicks[] += 1
        await_gui(s -> s["state"] == "paused" && s["completed"] == 2)
        @test viewer.time[] == 3
        @test viewer.history[].times[end]-viewer.history[].times[1] == Hour(12)
        @test size(viewer.history[].fields[:pres],3)==3
        @test count(isfinite,frame(viewer.history[],:rh,surface,3))>0
        viewer.viewmenu.i_selected[]=3
        viewer.tracker.source_menu.i_selected[]=2
        await_gui(s -> viewer.tracker.catalog[] isa ModelStormSet && length(viewer.tracker.catalog[].reports)==3)
        @test viewer.tracker.catalog[].source_path==viewer.history[].path
        @test viewer.tracker.clock[]==viewer.history[].times[end]
        viewer.tracker.source_menu.i_selected[]=1
        viewer.viewmenu.i_selected[]=2
        viewer.runmodel.clicks[] += 1
        viewer.pausemodel.clicks[] += 1
        await_gui(s -> s["state"] == "paused" && s["sequence"] == viewer.session[].sequence)
        if !isempty(ARGS)
            save(abspath(first(ARGS)),viewer.fig)
        end
        viewer.stopmodel.clicks[] += 1
        await_gui(s -> s["state"] == "stopped")
        wait(viewer.session[].process)
        @test success(viewer.session[].process)
    end
    println("LIVE_GUI_SMOKE_PASSED")
finally
    viewer.session[] !== nothing && stop_session!(viewer.session[])
    close(screen)
end
