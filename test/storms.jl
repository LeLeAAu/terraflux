using Test, Dates, TOML
include(joinpath(@__DIR__,"..","src","storms.jl"))
using .TerraFluxStorms
path = joinpath(@__DIR__,"..","scenarios","demo_storms.toml")
scenario = load_scenario(path)
@testset "Storm scenario and classification" begin
    @test scenario.provenance == "illustrative_scenario"
    @test length(unique(s.id for s in scenario.systems)) == 2
    for (wind,low,high) in ((34,:D,:S),(64,:S,:C1),(83,:C1,:C2),(96,:C2,:C3),(113,:C3,:C4),(137,:C4,:C5))
        @test storm_class("tropical",wind-0.001) == low
        @test storm_class("tropical",wind) == high
    end
    @test storm_class("subtropical",33) == :SD
    @test storm_class("subtropical",34) == :SS
    @test storm_class("extratropical",60) == :EX
    @test storm_class("disturbance",20) == :L
    @test storm_class("remnant",15) == :RL
    @test wind_value(1,:ms) ≈ 1852/3600
    @test wind_value(1,:kmh) == 1.852
    @test wind_value(1,:mph) ≈ 1.150779448
    @test_throws ArgumentError storm_class("tropical",NaN)
    @test_throws ArgumentError wind_value(1,:unknown)
    system = scenario.systems[1]
    @test storm_state(system,DateTime(1999)) === nothing
    @test storm_state(system,DateTime(2000,1,9)) === nothing
    @test storm_state(system,DateTime(2000,1,8)) === nothing
    state = storm_state(system,DateTime(2000,1,2))
    @test state.pressure_hpa == 1000
    halfway = storm_state(system,DateTime(2000,1,2,12))
    @test halfway.lon == 136
    @test halfway.lat == 13
    @test halfway.wind_knots == 55
    @test halfway.pressure_hpa == 992.5
    @test isempty(history_segments(system,DateTime(1999)))
    history = history_segments(system,DateTime(2000,1,2,12))
    @test length(history) == 2
    @test history[end].b == (136.,13.)
    @test history[1].category == :L
    @test history[2].category == :S
    @test length(history_segments(system,DateTime(2000,1,10))) == length(system.samples)-1
    # Interpolation crosses the short way around the dateline, without a map-wide chord.
    a=StormSample(DateTime(2000),179.,-20.,40.,nothing,"tropical",true)
    b=StormSample(DateTime(2000)+Hour(6),-179.,-22.,50.,nothing,"tropical",true)
    crossing=StormSystem("SEAM","Seam","",[a,b])
    middle=storm_state(crossing,DateTime(2000)+Hour(3))
    @test middle.lon == -180
    @test middle.lat == -21
    @test isempty(history_segments(crossing,b.time))
    sized=StormSystem("SIZE","Size","",[
        StormSample(a.time,a.lon,a.lat,a.wind_knots,nothing,a.kind,true,400.),
        StormSample(b.time,b.lon,b.lat,b.wind_knots,nothing,b.kind,true,800.)])
    @test storm_state(sized,a.time+Hour(3)).radius_km==600
    missing_size=StormSystem("MISSING","Missing","",[sized.samples[1],b])
    @test storm_state(missing_size,a.time+Hour(3)).radius_km===nothing
    # Input validation must reject ambiguous provenance, malformed clocks and duplicate IDs.
    mktempdir() do dir
        raw=TOML.parsefile(path)
        trial=joinpath(dir,"scenario.toml")
        function rejected(mutator)
            input=deepcopy(raw); mutator(input)
            open(trial,"w") do io; TOML.print(io,input); end
            @test_throws Exception load_scenario(trial)
        end
        rejected(d -> d["scenario"]["provenance"]="model_detection")
        rejected(d -> d["scenario"]["wind_average_minutes"]=10)
        rejected(d -> d["systems"][2]["id"]=d["systems"][1]["id"])
        rejected(d -> d["systems"][1]["samples"][2]["time"]=d["systems"][1]["samples"][1]["time"])
        rejected(d -> d["systems"][1]["samples"][1]["wind_knots"]=-1)
        rejected(d -> d["systems"][1]["samples"][1]["lat"]=91)
        rejected(d -> d["systems"][1]["samples"][1]["pressure_hpa"]=0)
        rejected(d -> d["systems"][1]["samples"][1]["radius_km"]=-1)
        rejected(d -> d["systems"][1]["samples"][1]["radius_km"]=NaN)
        raw["systems"][1]["samples"][1]["radius_km"]=750.
        open(trial,"w") do io;TOML.print(io,raw);end
        @test load_scenario(trial).systems[1].samples[1].radius_km==750.
    end
end
