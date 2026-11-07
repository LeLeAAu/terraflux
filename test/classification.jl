using Test, Dates, TOML
include(joinpath(@__DIR__,"..","src","storms.jl"))
using .TerraFluxStorms
standard=(wind_average_minutes=1,wind_height_m=10)
classify(kind,wind;kwargs...)=classify_system(kind,wind;standard...,kwargs...)
@testset "US system nature, wind basis and basin terminology" begin
    for (wind,below,at) in ((34,:D,:S),(64,:S,:C1),(83,:C1,:C2),(96,:C2,:C3),(113,:C3,:C4),(137,:C4,:C5))
        @test classify("tropical",prevfloat(Float64(wind))).category==below
        @test classify("tropical",wind).category==at
        @test classify("tropical",nextfloat(Float64(wind))).category==at
    end
    @test classify("tropical",63.9999).code=="TS" # never round into a typhoon
    @test classify("tropical",64;basin=:wpac).code=="TY"
    @test !classify("tropical",129.999;basin=:wpac).super_typhoon
    sty=classify("tropical",130;basin=:wpac)
    @test sty.code=="STY" && sty.super_typhoon && sty.sshws==4 && sty.equivalent
    @test classify("tropical",137;basin=:wpac).sshws==5
    for basin in (:atlantic,:epac,:cpac)
        @test classify("tropical",64;basin).code=="HU"
        major=classify("tropical",96;basin)
        @test major.code=="MH" && major.major_hurricane && !major.equivalent
        @test !classify("tropical",130;basin).super_typhoon
    end
    @test classify("tropical",130).code=="TC" # source did not declare a basin
    @test classify("tropical",130).equivalent
    @test classify("tropical",130;basin=:other).code=="TC"
    for (minutes,height) in ((nothing,nothing),(10,10),(1,100),(nothing,10),(1,nothing))
        c=classify_system("tropical",150;wind_average_minutes=minutes,wind_height_m=height)
        @test c.category==:UNKNOWN && c.sshws===nothing && !isempty(c.reason)
        @test c.nature=="tropical" && c.basin==:unspecified
    end
    for kind in ("low","disturbance","extratropical","posttropical","model_low")
        c=classify(kind,200;basin=:wpac)
        @test c.sshws===nothing && !c.super_typhoon && !c.major_hurricane
    end
    @test classify_system("model_low",200).category==:MODEL_LOW
    @test classify("subtropical",33.99).category==:SD
    @test classify("subtropical",34).category==:SS
    @test classify("subtropical",150;basin=:wpac).category==:SS
    @test classify("subtropical",150).sshws===nothing
    @test classify("remnant",33.99).category==:RL
    @test_throws ArgumentError classify("remnant",34)
    @test_throws ArgumentError classify("tropical",-1)
    @test_throws ArgumentError classify("tropical",NaN)
    @test_throws ArgumentError classify("tropical",Inf)
    @test_throws ArgumentError classify("invest",20) # operational label is not a nature
    @test_throws ArgumentError classify("tropical",100;basin=:jma)
    @test storm_class("tropical",150;wind_average_minutes=10)==:UNKNOWN
    for unit in (:kn,:ms,:kmh,:mph)
        # Display conversions do not enter the classifier or alter the sample.
        shown=wind_value(130,unit)
        @test isfinite(shown) && classify("tropical",130;basin=:wpac).code=="STY"
    end
    scenario=load_scenario(joinpath(@__DIR__,"..","scenarios","demo_storms.toml"))
    @test all(s.basin==:wpac for s in scenario.systems)
    @test occursin("Typhoon",storm_description(scenario.systems[1],storm_state(scenario.systems[1],DateTime(2000,1,4))))
    a=StormSample(DateTime(2000),140,20,20,nothing,"remnant",true)
    b=StormSample(DateTime(2000)+Hour(6),142,21,60,nothing,"extratropical",true)
    s=StormSystem("R","R","",[a,b])
    middle=storm_state(s,a.time+Hour(3))
    @test middle.lon==141 && middle.wind_knots==20 && storm_class(middle.kind,middle.wind_knots)==:RL
    @test storm_state(s,b.time).kind=="extratropical"
    mktempdir() do dir
        raw=TOML.parsefile(joinpath(@__DIR__,"..","scenarios","demo_storms.toml"))
        raw["systems"][2]["basin"]="atlantic"
        path=joinpath(dir,"scenario.toml")
        open(io->TOML.print(io,raw),path,"w")
        loaded=load_scenario(path)
        @test loaded.systems[1].basin==:wpac && loaded.systems[2].basin==:atlantic
        raw["systems"][1]["samples"][1]["kind"]="remnant"
        raw["systems"][1]["samples"][1]["wind_knots"]=34
        open(io->TOML.print(io,raw),path,"w")
        @test_throws ArgumentError load_scenario(path)
        raw["systems"][1]["samples"][1]["wind_knots"]=20
        raw["scenario"]["basin"]="typo"
        open(io->TOML.print(io,raw),path,"w")
        @test_throws Exception load_scenario(path)
    end
end
