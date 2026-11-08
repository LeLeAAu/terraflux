using Test,Dates,GLMakie
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer,.TerraFluxViewer.TerraFluxData,.TerraFluxViewer.TerraFluxLive
using .TerraFluxViewer.TerraFluxLive.TerraFluxSavedSessions
isempty(ARGS) && error("Provide a real saved session.toml (see test/session_resume.jl).")
archive=abspath(first(ARGS))
d=TerraFluxViewer.saved_weather(archive)
original=deepcopy(d.fields)
v=build_viewer(d;session_root=mktempdir(;prefix="TerraFlux persistence UI "))
screen=display(v.fig)
function click(widget)
    sleep(0.3)
    box=widget.layoutobservables.computedbbox[]
    events(v.fig).mouseposition[]=Tuple(box.origin.+box.widths./2)
    events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
    events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
end
function await_state(predicate)
    latest=Ref{Any}(nothing)
    result=timedwait(600;pollint=0.05) do
        latest[]=v.poll_live!()
        latest[]!==nothing && latest[]["state"]=="error" && error(latest[]["error"])
        latest[]!==nothing && predicate(latest[])
    end
    result==:ok || error("Timed out: $(v.livestatus[])")
    latest[]
end
try
    @testset "Real saved-session open/save controls and continued playback" begin
        click(v.savesession)
        @test v.session[]===nothing && occursin("Tạo phiên live",v.persistence_notice[])
        # Explorer's quoted path is accepted without requiring Enter.
        v.savedpath.displayed_string[]="\"$archive\""
        click(v.opensession)
        @test v.session[]!==nothing
        ready=await_state(s->s["state"]=="paused")
        @test ready["completed"]==1 && ready["pending_edit"] && ready["undo_available"]
        @test v.sourcemenu.selection[]==:live && v.time[]==2
        @test v.history[].times==d.times
        @test all(isequal(v.history[].fields[f],d.fields[f]) for f in keys(d.fields))
        @test occursin("Đã khôi phục",v.persistence_notice[])
        count=v.session[].sequence;current=v.session[]
        click(v.opensession)
        @test v.session[]===current && v.session[].sequence==count
        @test occursin("Kết thúc",v.persistence_notice[])
        click(v.savesession)
        saved=await_state(s->s["state"]=="paused" && s["sequence"]==v.session[].sequence)
        @test isempty(saved["command_error"])
        @test v.savedpath.displayed_string[]==saved["last_saved"]
        @test isfile(v.savedpath.displayed_string[]) && occursin("Đã lưu đầy đủ",v.persistence_notice[])
        @test saved_manifest(v.savedpath.displayed_string[])["pending_edit"]
        if length(ARGS)>1;save(ARGS[2],v.fig);end
        v.stepmodel.clicks[]+=1
        continued=await_state(s->s["state"]=="paused" && s["completed"]==2)
        @test !continued["pending_edit"] && length(v.history[].times)==3
        @test v.history[].times[end]==d.times[end]+Hour(6)
        @test all(isfinite,frame(v.history[],:temp,8,3))
        v.viewmenu.i_selected[]=2
        @test v.globe.scene.visible[]
        v.viewmenu.i_selected[]=3
        @test !v.globe.scene.visible[] && v.savesession.blockscene.visible[]
        stop_session!(v.session[];timeout=10)
        v.savedpath.displayed_string[]=joinpath(@__DIR__,"missing-session.toml")
        click(v.opensession)
        @test occursin("Không tìm thấy",v.persistence_notice[])
        @test all(isequal(d.fields[f],original[f]) for f in keys(original))
    end
    println("SESSION_VIEWER_PASSED")
finally
    v.session[]===nothing || stop_session!(v.session[])
    close(screen)
end
