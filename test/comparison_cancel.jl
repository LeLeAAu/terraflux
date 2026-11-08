using Test,TOML
include(joinpath(@__DIR__,"..","src","data.jl"));using .TerraFluxData
include(joinpath(@__DIR__,"..","src","live.jl"));using .TerraFluxLive
include(joinpath(@__DIR__,"..","src","comparison.jl"));using .TerraFluxComparison
using .TerraFluxLive.TerraFluxSavedSessions
baseline=abspath(first(ARGS));root=mktempdir(;prefix="TerraFlux AB cancel ")
@testset "Asynchronous baseline validation, cancellation and corrupt metadata" begin
    job=start_comparison(baseline;treatment=false,steps=1,root)
    try
        @test timedwait(120;pollint=0.05) do
            m=comparison_status(job)
            m["state"]=="error" && error(m["error"])
            m["phase"]=="initializing_a" && haskey(m,"child_pid")
        end == :ok
        @test saved_manifest(joinpath(job.directory,"baseline"))["model_time"]==saved_manifest(baseline)["model_time"]
        pid=comparison_status(job)["child_pid"]
        # Even when the status file is broken, cancellation must stop both processes.
        write(joinpath(job.directory,"comparison.toml"),"broken = [")
        stop_comparison!(job;timeout=1)
        @test !process_running(job.process)
        @test comparison_status(job)["state"] in ("stopped","error")
        Sys.islinux() && @test !ispath("/proc/$pid")
    finally
        process_running(job.process) && stop_comparison!(job)
    end
    corrupted=joinpath(root,"corrupted source");cp(dirname(baseline),corrupted)
    file=joinpath(corrupted,"state.jld2")
    open(file,"r+") do io;x=read(io,UInt8);seekstart(io);write(io,x⊻0x01);end
    bad=start_comparison(corrupted;treatment=false,steps=1,root)
    try
        @test timedwait(120;pollint=0.05) do
            comparison_status(bad)["state"]=="error"
        end == :ok
        wait(bad.process)
        @test occursin("checksum",comparison_status(bad)["error"])
        @test isempty(comparison_status(bad)["outputs_a"]) && isempty(comparison_status(bad)["outputs_b"])
    finally
        stop_comparison!(bad)
    end
end
