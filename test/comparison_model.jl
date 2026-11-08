using Test,Dates,TOML
include(joinpath(@__DIR__,"..","src","data.jl"));using .TerraFluxData
include(joinpath(@__DIR__,"..","src","live.jl"));using .TerraFluxLive
include(joinpath(@__DIR__,"..","src","comparison.jl"));using .TerraFluxComparison
using .TerraFluxLive.TerraFluxSavedSessions
isempty(ARGS) && error("Provide a saved session with no pending edits and at least 2 remaining chunks.")
baseline=abspath(ARGS[1]);meta=saved_manifest(baseline)
root=length(ARGS)>1 ? abspath(ARGS[2]) : mktempdir(;prefix="TerraFlux A B model ")
job=start_comparison(baseline;treatment=false,steps=2,root)
try
    @testset "Identical branches, paired time and portable A/B results" begin
        @test timedwait(900;pollint=0.1) do
            m=comparison_status(job)
            m["state"]=="error" && error(m["error"]*"\n"*read(joinpath(job.directory,"worker.log"),String))
            m["state"]=="complete"
        end == :ok
        wait(job.process);@test job.process.exitcode==0
        r=load_comparison(job.directory)
        @test r.times==[DateTime(meta["model_time"])+Hour(h) for h in (6,12)]
        @test length(r.meta["outputs_a"])==length(r.meta["outputs_b"])==2
        for f in FIELDS,k in (1,length(r.a.layers)),i in eachindex(r.times)
            v=comparison_values(r,f,k,i)
            mask=isfinite.(v.a)
            @test mask==isfinite.(v.b) && isapprox(v.a[mask],v.b[mask];atol=2e-4,rtol=2e-5)
        end
        @test !haskey(r.meta,"effect") && !r.meta["treatment"]
        for side in ("a","b")
            @test saved_manifest(joinpath(job.directory,r.meta["archive_"*side]))["completed"]==meta["completed"]+2
        end
        moved=joinpath(root,"moved results")
        cp(job.directory,moved);rm(job.directory;recursive=true)
        r2=load_comparison(moved)
        @test r2.times==r.times
        @test comparison_values(r2,:temp,8,1).delta==comparison_values(r,:temp,8,1).delta
        println("A/B result: $(joinpath(moved,"comparison.toml"))");flush(stdout)
        # A same-length change must fail integrity checks, even though time/shape still match.
        target=joinpath(moved,r2.meta["outputs_b"][1]["path"])
        original=Ref{UInt8}()
        open(target,"r+") do io;seekend(io);at=position(io)-1;seek(io,at);original[]=read(io,UInt8);seek(io,at);write(io,original[]⊻0x01);end
        @test_throws ErrorException load_comparison(moved)
        open(target,"r+") do io;seekend(io);seek(io,position(io)-1);write(io,original[]);end
    end
    println("COMPARISON_MODEL_PASSED")
finally
    # The original folder may have been moved after a completed job.
    process_running(job.process) && stop_comparison!(job)
end
