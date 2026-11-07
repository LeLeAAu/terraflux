using Test,TOML
include(joinpath(@__DIR__,"..","src","live.jl"))
using .TerraFluxLive
@testset "Edits cannot be skipped by a following run command" begin
    mktempdir() do dir
        mkpath(joinpath(dir,"commands"))
        for (id,action) in ((1,"thermal"),(2,"run"),(3,"pause"))
            atomic_toml(joinpath(dir,"commands",lpad(string(id),6,'0')*".toml"),Dict("sequence"=>id,"action"=>action))
        end
        @test TerraFluxLive.next_command(dir,0)["action"]=="thermal"
        @test TerraFluxLive.next_command(dir,1)["action"]=="run"
        @test TerraFluxLive.next_command(dir,2)["action"]=="pause"
        @test TerraFluxLive.next_command(dir,3)===nothing
        atomic_toml(joinpath(dir,"commands","000004.toml"),Dict("sequence"=>4,"action"=>"stop"))
        @test TerraFluxLive.next_command(dir,0)["action"]=="stop"
    end
end
