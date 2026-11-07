using Test,Dates,SpeedyWeather
include(joinpath(@__DIR__,"..","src","model_progress.jl"))
using .TerraFluxModelProgress
@testset "Progress follows completed model time and preserves validation" begin
    events=NamedTuple[];start=DateTime(2000)
    p=ModelProgress(start,start+Day(1),e->push!(events,e))
    vars(t)=(prognostic=(clock=(time=t,),),)
    SpeedyWeather.initialize!(p,vars(start),nothing)
    @test only(events).percent==0 && only(events).eta_seconds==-1
    SpeedyWeather.callback!(p,vars(start+Hour(1)),nothing)
    @test length(events)==1 # 4% is below the next reporting threshold.
    SpeedyWeather.callback!(p,vars(start+Hour(2)),nothing)
    @test last(events).percent==8 && last(events).hours_done==2
    @test last(events).hours_total==24 && last(events).eta_seconds>=0
    SpeedyWeather.callback!(p,vars(start+Hour(12)),nothing)
    @test last(events).percent==50 && DateTime(last(events).model_time)==start+Hour(12)
    n=length(events)
    SpeedyWeather.finalize!(p,vars(start+Hour(12)),nothing)
    @test length(events)==n && last(events).percent==50
    report_progress!(p,start+Hour(12);phase="validating",force=true)
    @test last(events).phase=="validating" && last(events).percent==50
    SpeedyWeather.callback!(p,vars(start+Day(1)),nothing)
    @test last(events).percent==100 && last(events).eta_seconds==0
    @test last(events).phase=="integrating" # 100% integration is not certified completion.
    @test p.start==start && p.finish==start+Day(1)
end
