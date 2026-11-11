using Test,Dates,TOML,Random,SpeedyWeather
include(joinpath(@__DIR__,"..","src","live.jl"))
using .TerraFluxLive
function wait_ack(session)
    latest=Ref{Any}(nothing)
    @assert timedwait(600;pollint=0.05) do
        latest[]=read_status(session)
        latest[]["state"]=="error" && error(latest[]["error"])
        latest[]["state"]=="paused" && get(latest[],"sequence",0)==session.sequence
    end == :ok
    latest[]
end
function snapshot(session)
    send_command!(session,"save")
    status=wait_ack(session)
    @test isempty(status["command_error"])
    SpeedyWeather.jldopen(joinpath(dirname(status["last_saved"]),"state.jld2"),"r") do f
        (variables=f["variables"],rng=f["rng"])
    end
end
session=start_session(;root=mktempdir(),max_chunks=4)
try
    @testset "Expanded live interventions and rejected-state rollback" begin
        wait_ack(session)
        send_command!(session,"step");wait_ack(session)
        baseline=snapshot(session)
        patch=(lon=130.,lat=20.,radius_km=3000.,layer=8,delta_k=250.)
        send_command!(session,"thermal";patch)
        warm=wait_ack(session)
        @test isempty(warm["command_error"]) && warm["pending_edit"]
        send_command!(session,"undo_edit");wait_ack(session)
        send_command!(session,"thermal";patch=merge(patch,(delta_k=-1e6,)))
        failed=wait_ack(session)
        @test occursin(">0 K",failed["command_error"])
        @test !failed["pending_edit"] && !failed["undo_available"]
        restored=snapshot(session)
        for name in (:temperature,:pressure,:vorticity,:divergence,:humidity)
            @test getproperty(restored.variables.prognostic,name)==getproperty(baseline.variables.prognostic,name)
        end
        @test restored.variables.prognostic.clock.time==baseline.variables.prognostic.clock.time
        @test rand(copy(restored.rng))==rand(copy(baseline.rng))
        # Stronger-than-former-limit vortex, followed by exact undo.
        vortex=(lon=130.,lat=35.,radius_km=3000.,pressure_drop_hpa=50.,depth=0.75)
        send_command!(session,"vortex";patch=vortex)
        inserted=wait_ack(session)
        @test isempty(inserted["command_error"]) && inserted["pending_edit"]
        send_command!(session,"undo_edit");wait_ack(session)
        after=snapshot(session)
        @test after.variables.prognostic.temperature==baseline.variables.prognostic.temperature
        @test after.variables.prognostic.pressure==baseline.variables.prognostic.pressure
    end
finally
    stop_session!(session)
end
