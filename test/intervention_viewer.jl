using Test,Dates,TOML,GLMakie
include(joinpath(@__DIR__,"..","src","viewer.jl"))
using .TerraFluxViewer,.TerraFluxViewer.TerraFluxData,.TerraFluxViewer.TerraFluxLive
d=load_weather(joinpath(@__DIR__,"..","run_0001","output.nc"))
original=deepcopy(d.fields)
v=build_viewer(d;session_root=mktempdir(;prefix="TerraFlux thermal UI "))
screen=display(v.fig)
function click(widget)
    # Makie Buttons distinguish a second rapid click as a double-click.
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
ack(s)=s["state"]=="paused" && s["sequence"]==v.session[].sequence
try
    @testset "Scoped thermal controls, real model edits and undo" begin
        click(v.interventionbutton)
        @test v.intervention_open[] && !v.overlay_open[]
        @test v.intervention.menu.blockscene.visible[] && !v.fieldmenu.blockscene.visible[]
        pixel=Makie.project(v.ax.scene,Point3f(130,20,0))
        events(v.fig).mouseposition[]=Tuple(pixel[1:2].+v.ax.scene.viewport[].origin)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(v.fig).mousebutton[]=Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test v.selected[]!==nothing && !isempty(v.intervention.ring[])
        v.intervention.apply.clicks[]+=1
        @test occursin("phiên live",v.intervention.message[])
        click(v.intervention.menu)
        @test v.intervention.menu.is_open[]
        v.viewmenu.i_selected[]=3
        @test !v.intervention.menu.is_open[] && !v.intervention.menu.blockscene.visible[]
        v.viewmenu.i_selected[]=2
        click(v.interventionbutton)
        @test v.intervention_open[] && v.intervention.menu.blockscene.visible[]
        v.viewmenu.i_selected[]=1
        click(v.interventionbutton)
        v.intervention.radius.displayed_string[]="3000"
        v.intervention.delta.displayed_string[]="2"
        v.newrun.clicks[]+=1
        await_state(s->s["state"]=="paused")
        v.stepmodel.clicks[]+=1
        await_state(s->s["state"]=="paused" && s["completed"]==1)
        before=deepcopy(v.history[].fields)
        count=v.session[].sequence
        v.sourcemenu.i_selected[]=1
        v.intervention.apply.clicks[]+=1
        @test v.session[].sequence==count
        @test occursin("Phiên mô phỏng",v.intervention.message[])
        v.sourcemenu.i_selected[]=2
        set_close_to!(v.slider,1)
        v.intervention.apply.clicks[]+=1
        @test v.session[].sequence==count
        set_close_to!(v.slider,2)
        v.intervention.apply.clicks[]+=1
        status=await_state(ack)
        @test isempty(status["command_error"]) && status["pending_edit"] && status["undo_available"]
        @test status["model_time"]==string(v.history[].times[end]) && status["completed"]==1
        record=joinpath(v.session[].directory,"edits",lpad(string(v.session[].sequence),6,'0'),"event.toml")
        event=TOML.parsefile(record)
        @test event["status"]=="applied" && event["effect"]["heat_dry_approx_j"]>0
        @test isfile(event["checkpoint"]) && isfile(joinpath(dirname(record),"after.jld2"))
        @test all(isequal(before[f],v.history[].fields[f]) for f in keys(before))
        @test occursin("trước tác động",v.intervention.message[])
        v.intervention.undo.clicks[]+=1
        status=await_state(ack)
        @test !status["pending_edit"] && !status["undo_available"] && isempty(status["command_error"])
        v.intervention.apply.clicks[]+=1
        status=await_state(ack)
        @test status["pending_edit"] && isempty(status["command_error"])
        if !isempty(ARGS);save(first(ARGS),v.fig);end
        v.stepmodel.clicks[]+=1
        status=await_state(s->ack(s) && s["completed"]==2)
        @test !status["pending_edit"] && !status["undo_available"]
        @test v.history[].times[end]-v.history[].times[1]==Hour(12)
        @test all(isfinite,frame(v.history[],:temp,8,3))
        v.intervention.undo.clicks[]+=1
        status=await_state(ack)
        @test !isempty(status["command_error"]) && status["state"]=="paused"
        # A malformed layer bypassing the UI is rejected and rolled back by the worker.
        p=merge(v.intervention.spec(),(layer=32,))
        send_command!(v.session[],"thermal";patch=p)
        status=await_state(ack)
        @test !isempty(status["command_error"]) && !status["pending_edit"]
        @test status["model_time"]==string(v.history[].times[end])
        @test all(isequal(d.fields[f],original[f]) for f in keys(original))
    end
    println("INTERVENTION_VIEWER_PASSED")
finally
    v.session[]===nothing || stop_session!(v.session[])
    close(screen)
end
