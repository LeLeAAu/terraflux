using Test,TOML,Dates
include(joinpath(@__DIR__,"..","src","live.jl"))
include(joinpath(@__DIR__,"..","src","data.jl"))
using .TerraFluxLive,.TerraFluxData
using .TerraFluxLive.TerraFluxSavedSessions
root=isempty(ARGS) ? mktempdir(;prefix="TerraFlux resume test ") : abspath(first(ARGS))
mkpath(root)
println("Resume validation directory: $root");flush(stdout)
a=start_session(;root,truncation=21,layers=8,max_chunks=4)
resumed=Ref{Union{Nothing,LiveSession}}(nothing)
function await(s,predicate)
    latest=Ref{Any}(nothing)
    result=timedwait(600;pollint=0.05) do
        latest[]=read_status(s)
        latest[]["state"]=="error" && error(latest[]["error"]*"\n"*read(joinpath(s.directory,"worker.log"),String))
        predicate(latest[])
    end
    result==:ok || error("Timed out: $(latest[]) in $(s.directory)")
    latest[]
end
ack(s)=t->t["state"]=="paused" && t["sequence"]==s.sequence
try
    @testset "Save, stop, relocate, restore pending heat, undo and continue" begin
        await(a,s->s["state"]=="paused")
        send_command!(a,"step");await(a,s->s["completed"]==1 && s["state"]=="paused")
        patch=(lon=130.,lat=20.,radius_km=3000.,layer=8,delta_k=2.)
        send_command!(a,"thermal";patch);heated=await(a,ack(a))
        @test heated["pending_edit"] && isempty(heated["command_error"])
        send_command!(a,"save");saved=await(a,ack(a))
        @test isempty(saved["command_error"]) && isfile(saved["last_saved"])
        bundle=saved["last_saved"];meta=saved_manifest(bundle)
        @test meta["model_time"]=="2000-01-01T06:00:00" && meta["completed"]==1
        @test meta["pending_edit"] && meta["undo_available"]
        @test all(!isabspath(e["path"]) for e in meta["payloads"])
        @test "journal/$(basename(a.directory))/events/000002.toml" in meta["journal"]
        @test length(meta["journal"])==4 # step, thermal, save commands; thermal event
        send_command!(a,"step");reference=await(a,s->s["completed"]==2 && s["state"]=="paused")
        expected=load_weather(last(reference["files"]))
        stop_session!(a;timeout=10)
        moved=joinpath(root,"relocated archive");cp(dirname(bundle),moved)
        println("Relocated archive: $moved");flush(stdout)
        # Continuation must depend only on the archive, not the original session paths.
        rm(a.directory;recursive=true)
        rm(dirname(bundle);recursive=true)
        b=resume_session(moved;root)
        resumed[]=b
        restored=await(b,s->s["state"]=="paused")
        @test restored["completed"]==1 && restored["model_time"]==meta["model_time"]
        @test restored["pending_edit"] && restored["undo_available"]
        @test all(startswith(f,b.directory) for f in restored["files"])
        @test isfile(joinpath(b.directory,"provenance",basename(a.directory),"events","000002.toml"))
        @test isempty(readdir(joinpath(b.directory,"commands"))) # journals are not replayed
        send_command!(b,"undo_thermal");undone=await(b,ack(b))
        @test !undone["pending_edit"] && isempty(undone["command_error"])
        send_command!(b,"thermal";patch);redone=await(b,ack(b))
        @test redone["pending_edit"] && isempty(redone["command_error"])
        send_command!(b,"step");continued=await(b,s->s["state"]=="paused" && s["completed"]==2)
        actual=load_weather(last(continued["files"]))
        @test actual.times==expected.times && actual.times[end]==DateTime(2000,1,1,12)
        for f in keys(expected.fields)
            x=selectdim(expected.fields[f],ndims(expected.fields[f]),2)
            y=selectdim(actual.fields[f],ndims(actual.fields[f]),2)
            @test isapprox(x,y;atol=2e-4,rtol=2e-5)
        end
        @test !continued["pending_edit"] && !continued["undo_available"]
        # A second archive includes both inherited and newly calculated chunks.
        send_command!(b,"save");twice=await(b,ack(b))
        second=saved_manifest(twice["last_saved"])
        @test second["completed"]==2
        @test all(in(second["journal"]),meta["journal"])
        @test length(second["journal"])==10 # inherited 4; new undo/thermal/step/save + two events
    end
    println("SESSION_RESUME_PASSED")
finally
    process_running(a.process) && stop_session!(a)
    resumed[]===nothing || stop_session!(resumed[])
end
