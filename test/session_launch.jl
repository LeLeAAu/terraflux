# Startup from a multi-chunk archive and a save followed by stop before GUI polling.
using Test,GLMakie
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer,.TerraFluxViewer.TerraFluxLive
using .TerraFluxViewer.TerraFluxLive.TerraFluxSavedSessions
archive=abspath(first(ARGS))
meta=saved_manifest(archive)
data=TerraFluxViewer.saved_weather(archive)
v=build_viewer(data;resume_bundle=archive,session_root=mktempdir(;prefix="TerraFlux startup "))
screen=display(v.fig)
try
    @testset "Launcher restore, inherited history and save-then-stop" begin
        result=timedwait(600;pollint=0.05) do
            s=v.poll_live!()
            s["state"]=="error" && error(s["error"])
            s["state"]=="paused"
        end
        @test result==:ok
        @test length(v.history[].times)==meta["completed"]+1
        @test v.history[].times==data.times
        @test occursin("/ $(meta["config"]["max_chunks"]*6) giờ",v.livestatus[])
        @test read_status(v.session[])["model_time"]==meta["model_time"]
        v.savesession.clicks[]+=1
        @test timedwait(120;pollint=0.01) do
            s=read_status(v.session[])
            s["state"]=="paused" && s["sequence"]==v.session[].sequence
        end == :ok
        # The user stops after saving completes, before the next GUI timer poll.
        stop_session!(v.session[])
        s=v.poll_live!()
        @test s["state"]=="stopped" && occursin("Đã lưu đầy đủ",v.persistence_notice[])
        @test saved_manifest(s["last_saved"])["completed"]==meta["completed"]
    end
    println("SESSION_LAUNCH_PASSED")
finally
    stop_session!(v.session[])
    close(screen)
end
