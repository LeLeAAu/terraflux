# Integration test: starts a real isolated SpeedyWeather process, not a mock.
using Test, Dates, TOML
include(joinpath(@__DIR__,"..","src","live.jl"))
include(joinpath(@__DIR__,"..","src","data.jl"))
using .TerraFluxLive, .TerraFluxData
function wait_status(session, predicate;timeout=600)
    latest = Ref{Any}(nothing)
    result = timedwait(timeout;pollint=0.02) do
        latest[] = read_status(session)
        latest[]["state"] == "error" && error(latest[]["error"])
        predicate(latest[])
    end
    result == :ok || error("Worker timed out: $(latest[]). Logs: $(session.directory)")
    latest[]
end
root = isempty(ARGS) ? mktempdir() : abspath(first(ARGS))
session = start_session(;root,max_chunks=4)
println("Session: ",session.directory); flush(stdout)
try
    @testset "Real simulation control and closed-file publication" begin
        ready = wait_status(session,s -> s["state"] == "paused")
        @test ready["completed"] == 0
        send_command!(session,"run")
        wait_status(session,s -> s["state"] == "running")
        send_command!(session,"pause")
        paused = wait_status(session,s -> s["state"] == "paused" && s["sequence"] == session.sequence)
        @test 1 <= paused["completed"] < 4
        count = paused["completed"]
        sleep(0.3)
        @test read_status(session)["completed"] == count
        send_command!(session,"step")
        stepped = wait_status(session,s -> s["completed"] == count+1 && s["state"] == "paused")
        @test length(stepped["files"]) == count+1
        send_command!(session,"run")
        done = wait_status(session,s -> s["state"] == "complete")
        wait(session.process)
        @test success(session.process)
        @test done["completed"] == 4
        chunks = [load_live_chunk(path;initial=i == 1) for (i,path) in enumerate(done["files"])]
        history = reduce(append_weather,chunks)
        @test length(history.times) == 5
        @test history.times[end]-history.times[1] == Day(1)
        @test all(diff(history.times) .== Hour(6))
        @test length(unique(history.times)) == 5
        @test frame(history,:temp,8,5) == frame(chunks[end],:temp,8,2)
        @test maximum(abs.(frame(history,:temp,8,5)-frame(history,:temp,8,1))) > 0
        @test all(all(isfinite,v) for (f,v) in history.fields if f != :mslp)
        @test all(isnan,history.fields[:mslp][:,:,1])
        @test all(isfinite,history.fields[:mslp][:,:,2:end])
        @test all(isfile(joinpath(dirname(path),"restart.jld2")) for path in done["files"])
        @test isfile(joinpath(session.directory,"config.toml"))
        @test length(readdir(joinpath(session.directory,"commands"))) == 4
        @test_throws ArgumentError send_command!(session,"unsupported")
    end
    println("LIVE_SMOKE_PASSED")
finally
    stop_session!(session)
end
