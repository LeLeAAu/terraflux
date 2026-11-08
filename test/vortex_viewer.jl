using Test,Dates,TOML,GLMakie
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer,.TerraFluxViewer.TerraFluxData,.TerraFluxViewer.TerraFluxLive
using .TerraFluxViewer.TerraFluxLive.TerraFluxSavedSessions
baseline=abspath(ARGS[1]);d=TerraFluxViewer.saved_weather(baseline);original=deepcopy(d.fields)
root=length(ARGS)>2 ? abspath(ARGS[3]) : mktempdir(;cleanup=false);mkpath(root)
v=build_viewer(d;resume_bundle=baseline,session_root=root);screen=display(v.fig)
function click(widget)
    sleep(0.3);b=widget.layoutobservables.computedbbox[]
    events(v.fig).mouseposition[]=Tuple(b.origin.+b.widths./2)
    events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
    events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
end
function await_state(predicate)
    latest=Ref{Any}(nothing)
    @assert timedwait(600;pollint=0.1) do
        latest[]=v.poll_live!()
        latest[]["state"]=="error" && error(latest[]["error"])
        predicate(latest[])
    end == :ok
    latest[]
end
ack(s)=s["state"]=="paused" && s["sequence"]==v.session[].sequence
try
    @testset "Native vortex preview, model insertion, archive and undo" begin
        click(v.vortexbutton)
        @test v.vortex_open[] && !v.intervention_open[] && !v.overlay_open[]
        @test v.vortex.depth.blockscene.visible[] && !v.fieldmenu.blockscene.visible[]
        click(v.vortex.suggested)
        @test v.selected[]!==nothing && !isempty(v.vortex.ring[])
        @test occursin("Tham chiếu",v.vortex.summary[])
        click(v.vortex.depth);@test v.vortex.depth.is_open[]
        v.viewmenu.i_selected[]=3
        @test !v.vortex.depth.is_open[] && !v.vortex.depth.blockscene.visible[]
        v.viewmenu.i_selected[]=2;click(v.vortexbutton)
        @test v.vortex_open[] && v.globe.scene.visible[]
        click(v.interventionbutton)
        @test !v.vortex_open[] && v.intervention_open[]
        v.viewmenu.i_selected[]=1;click(v.vortexbutton)
        ready=await_state(s->s["state"]=="paused")
        before=deepcopy(v.history[].fields);count=v.session[].sequence
        v.vortex.radius.displayed_string[]="500";click(v.vortex.apply)
        @test v.session[].sequence==count
        v.vortex.radius.displayed_string[]="3000"
        click(v.vortex.apply);applied=await_state(ack)
        @test isempty(applied["command_error"]) && applied["pending_edit"] && applied["undo_available"]
        @test applied["model_time"]==ready["model_time"]
        @test all(isequal(before[f],v.history[].fields[f]) for f in keys(before))
        event=TOML.parsefile(joinpath(v.session[].directory,"edits",lpad(string(v.session[].sequence),6,'0'),"event.toml"))
        @test event["action"]=="vortex" && event["effect"]["projected_peak_wind_mps"]>1
        @test event["effect"]["projected_wind_relative_l2"]<=0.35
        click(v.savesession);saved=await_state(ack)
        meta=saved_manifest(saved["last_saved"])
        @test meta["pending_edit"] && meta["undo_available"]
        click(v.vortex.undo);undone=await_state(ack)
        @test !undone["pending_edit"] && !undone["undo_available"] && isempty(undone["command_error"])
        click(v.vortex.apply);await_state(ack)
        click(v.stepmodel)
        next=await_state(s->s["state"]=="paused" && s["completed"]==ready["completed"]+1)
        @test !next["pending_edit"] && !next["undo_available"]
        @test v.history[].times[end]==d.times[end]+Hour(6)
        @test all(isfinite,frame(v.history[],:wind,8,length(v.history[].times)))
        @test all(isequal(d.fields[f],original[f]) for f in keys(original))
        v.fieldmenu.i_selected[]=findfirst(==(:wind),FIELDS)
        length(ARGS)>1 && save(ARGS[2],v.fig)
    end
    println("VORTEX_VIEWER_PASSED")
finally
    stop_session!(v.session[]);close(screen)
end
