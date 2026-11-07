using Test,TOML
project=abspath(joinpath(@__DIR__,".."))
worker=joinpath(project,"src","batch_worker.jl")
@testset "Worker records configuration and library-load failures" begin
    mktempdir(;prefix="TerraFlux worker errors ") do root
        for missing_library in (false,true)
            directory=mktempdir(root)
            open(joinpath(directory,"config.toml"),"w") do io
                TOML.print(io,Dict("days"=>0,"truncation"=>21,"layers"=>8,"output_hours"=>24,"seed"=>123))
            end
            envdir=missing_library ? mktempdir(root) : project
            cmd=`$(Base.julia_cmd()) --startup-file=no --depwarn=error --threads=1 --project=$envdir $worker $directory`
            process=open(joinpath(directory,"worker.log"),"w") do io
                run(pipeline(ignorestatus(cmd),stdout=io,stderr=io))
            end
            @test !success(process)
            status=TOML.parsefile(joinpath(directory,"status.toml"))
            status["state"]=="error" || error(read(joinpath(directory,"worker.log"),String))
            @test status["state"]=="error" && !haskey(status,"output_path")
            @test occursin(missing_library ? "SpeedyWeather" : "Số ngày",status["error"])
            @test occursin("Stacktrace",status["error_detail"])
            log=read(joinpath(directory,"worker.log"),String)
            @test occursin("LỖI WORKER",log) && occursin(status["error_detail"],log)
            @test !occursin("world prior",log) && !occursin("too new",log)
        end
    end
end
