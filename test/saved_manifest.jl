using Test,TOML,Dates
include(joinpath(@__DIR__,"..","src","saved_sessions.jl"))
using .TerraFluxSavedSessions
@testset "Saved session format, versions and payload integrity" begin
    mktempdir(;prefix="TerraFlux saved metadata ") do root
        mkpath(joinpath(root,"history"))
        write(joinpath(root,"state.jld2"),"state fixture")
        write(joinpath(root,"history","chunk_000001.nc"),"history fixture")
        meta=Dict("format"=>"terraflux.saved-session","format_version"=>1,
            "model"=>"PrimitiveWetModel","backend"=>"CPU","julia_version"=>string(VERSION),
            "speedyweather_version"=>speedy_version(),"completed"=>1,"model_time"=>"2000-01-01T06:00:00",
            "config"=>Dict{String,Any}("truncation"=>21,"layers"=>8,"chunk_hours"=>6,"max_chunks"=>4),
            "undo_available"=>false,"pending_edit"=>false,"undo_previous_pending"=>false,"edit_summary"=>"","history"=>["history/chunk_000001.nc"],
            "payloads"=>[payload_entry(root,n) for n in ("state.jld2","history/chunk_000001.nc")])
        file=joinpath(root,"session.toml")
        put(m)=open(io->TOML.print(io,m),file,"w")
        put(meta)
        @test saved_manifest(root)["completed"]==1
        @test saved_manifest(file)["model_time"]=="2000-01-01T06:00:00"
        for change in (m->m["format_version"]=9,m->m["julia_version"]="0.0.0",m->m["speedyweather_version"]="0.0.0",
            m->m["history"]=["../outside.nc"],m->m["completed"]=2,m->m["config"]["layers"]=3,
            m->m["journal"]=["journal/../../outside.toml"],m->m["config"]["max_chunks"]=4.5)
            bad=deepcopy(meta);change(bad);put(bad)
            @test_throws Exception saved_manifest(file)
        end
        put(meta)
        write(joinpath(root,"state.jld2"),"STATE fixture") # Same length, different bytes.
        @test_throws Exception saved_manifest(file)
        @test saved_manifest(file;verify=false)["completed"]==1
        rm(joinpath(root,"state.jld2"))
        @test_throws Exception saved_manifest(file;verify=false)
    end
end
