using Test
include(joinpath(@__DIR__,"..","src","live.jl"))
using .TerraFluxLive
@testset "Closing an active worker" begin
    root = mktempdir()
    session = start_session(;root,max_chunks=1)
    try
        @test process_running(session.process)
        stop_session!(session;timeout=0.1)
        @test process_exited(session.process)
        @test isfile(joinpath(session.directory,"config.toml"))
        @test read_status(session)["state"] in ("stopped","error")
    finally
        stop_session!(session)
    end
end
