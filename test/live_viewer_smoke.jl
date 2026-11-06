# End-to-end GUI test with a real worker, display and OpenGL required.
using GLMakie, Test, Dates
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer
using .TerraFluxViewer.TerraFluxData
using .TerraFluxViewer.TerraFluxLive
path = joinpath(@__DIR__,"..","run_0001","output.nc")
data = load_weather(path)
root = mktempdir(;prefix="terraflux gui test ")
viewer = build_viewer(data;session_root=root)
screen = display(viewer.fig)
function await_gui(predicate;timeout=600)
    result = timedwait(timeout;pollint=0.05) do
        status = viewer.poll_live!()
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
        await_gui(s -> s !== nothing && s["state"] == "paused")
        viewer.selected[] = (60,30)
        viewer.stepmodel.clicks[] += 1
        await_gui(s -> s["state"] == "paused" && s["completed"] == 1)
        @test viewer.history[] !== nothing
        @test length(viewer.history[].times) == 2
        @test viewer.time[] == 2
        @test viewer.slider.range[] == 1:2
        @test viewer.selected[] == (60,30)
        @test viewer.mapvalues[][1:end-1,:] == frame(viewer.history[],:temp,8,2)
        viewer.sourcemenu.i_selected[] = 1
        @test viewer.mapvalues[][1:end-1,:] == frame(data,:temp,8,41)
        @test viewer.slider.range[] == 1:41
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
