module TerraFluxStorms
using Dates, TOML
export StormSample, StormSystem, StormScenario, load_scenario, storm_state, storm_class,
       history_segments, wind_value, CATEGORY_STYLES

const CATEGORY_STYLES = Dict(
    :MODEL_LOW => ("L?", "Ứng viên xoáy mô hình", "#84ccd7"),
    :L => ("L", "Nhiễu động", "#50ddea"), :EX => ("EX", "Ngoại nhiệt đới", "#b6bac4"),
    :RL => ("×", "Áp thấp tàn dư", "#8f95a3"), :D => ("D", "Áp thấp nhiệt đới", "#469cf7"),
    :SD => ("SD", "Áp thấp cận nhiệt đới", "#ad78ed"), :S => ("S", "Bão nhiệt đới", "#67ed52"),
    :SS => ("SS", "Bão cận nhiệt đới", "#b4f09a"),
    :C1 => ("1", "Cấp 1", "#f3f65b"), :C2 => ("2", "Cấp 2", "#f8c448"),
    :C3 => ("3", "Cấp 3", "#fa963a"), :C4 => ("4", "Cấp 4", "#f2534d"), :C5 => ("5", "Cấp 5", "#f667c2"))
const KINDS = ("disturbance","tropical","subtropical","extratropical","remnant")
struct StormSample
    time::DateTime
    lon::Float64
    lat::Float64
    wind_knots::Float64
    pressure_hpa::Union{Nothing,Float64}
    kind::String
    active::Bool
end
struct StormSystem
    id::String
    name::String
    local_name::String
    samples::Vector{StormSample}
end
struct StormScenario
    title::String
    provenance::String
    systems::Vector{StormSystem}
end

function load_scenario(path)
    input = TOML.parsefile(path)
    meta = input["scenario"]
    meta["provenance"] == "illustrative_scenario" || error("Bản này chỉ nhận kịch bản minh họa được khai báo rõ.")
    meta["wind_average_minutes"] == 1 && meta["wind_height_m"] == 10 ||
        error("Thang gió của kịch bản phải là gió 1 phút ở 10 m, đơn vị knot.")
    systems = StormSystem[]
    for system in input["systems"]
        id = String(system["id"])
        !isempty(strip(id)) && all(s -> s.id != id,systems) || error("ID hệ thống rỗng hoặc trùng: $id")
        samples = StormSample[]
        for raw in system["samples"]
            lon,lat,wind = Float64(raw["lon"]),Float64(raw["lat"]),Float64(raw["wind_knots"])
            all(isfinite,(lon,lat,wind)) && -180 <= lon <= 180 && -90 <= lat <= 90 && wind >= 0 || error("Tọa độ/gió không hợp lệ: $id")
            pressure = haskey(raw,"pressure_hpa") ? Float64(raw["pressure_hpa"]) : nothing
            pressure === nothing || (isfinite(pressure) && pressure > 0) || error("Áp suất không hợp lệ: $id")
            kind = String(raw["kind"])
            kind in KINDS || error("Loại hệ thống không hỗ trợ: $kind")
            time = DateTime(raw["time"])
            isempty(samples) || time > samples[end].time || error("Mốc thời gian phải tăng nghiêm ngặt: $id")
            isempty(samples) || samples[end].active || error("Không tái sử dụng ID sau khi hệ thống đã tan: $id")
            push!(samples,StormSample(time,lon,lat,wind,pressure,kind,get(raw,"active",true)))
        end
        length(samples) >= 2 || error("Mỗi hệ thống cần ít nhất hai mốc: $id")
        push!(systems,StormSystem(id,String(system["name"]),String(get(system,"local_name","")),samples))
    end
    !isempty(systems) || error("Kịch bản chưa có hệ thống.")
    StormScenario(String(meta["title"]),String(meta["provenance"]),systems)
end

"SSHWS lower bounds in knots for declared 1-minute, 10-m sustained winds."
function storm_class(kind, wind)
    kind == "model_low" && isfinite(wind) && wind >= 0 && return :MODEL_LOW
    kind in KINDS && isfinite(wind) && wind >= 0 || throw(ArgumentError("Loại/gió không hợp lệ"))
    kind == "disturbance" && return :L
    kind == "extratropical" && return :EX
    kind == "remnant" && return :RL
    kind == "subtropical" && return wind < 34 ? :SD : :SS
    bounds = (34,64,83,96,113,137)
    categories = (:D,:S,:C1,:C2,:C3,:C4,:C5)
    categories[1+count(b -> wind >= b,bounds)]
end
wind_value(knots, unit) = unit == :kn ? knots : unit == :ms ? knots*1852/3600 :
    unit == :kmh ? knots*1.852 : unit == :mph ? knots*1852/1609.344 : throw(ArgumentError("Đơn vị gió không hỗ trợ"))
wraplon(x) = mod(x+180,360)-180

"Position/wind are linearly interpolated; kind changes only at declared timestamps."
function storm_state(system::StormSystem, time::DateTime)
    samples = system.samples
    time < samples[1].time && return nothing
    time > samples[end].time && return nothing  # never extrapolate a future storm
    index = searchsortedlast(getfield.(samples,:time),time)
    a = samples[index]
    !a.active && return nothing
    a.kind == "model_low" && time != a.time && return nothing
    (time == a.time || index == length(samples)) && return a
    b = samples[index+1]
    fraction = Dates.value(time-a.time)/Dates.value(b.time-a.time)
    lon = wraplon(a.lon+fraction*wraplon(b.lon-a.lon))
    lat = a.lat+fraction*(b.lat-a.lat)
    wind = a.wind_knots+fraction*(b.wind_knots-a.wind_knots)
    pressure = a.pressure_hpa === nothing || b.pressure_hpa === nothing ? nothing :
        a.pressure_hpa+fraction*(b.pressure_hpa-a.pressure_hpa)
    StormSample(time,lon,lat,wind,pressure,a.kind,true)
end

"Completed history only, colored by the state at each segment's start; no dateline chord."
function history_segments(system, time)
    samples = filter(s -> s.time <= time,system.samples)
    current = storm_state(system,time)
    if current !== nothing && (isempty(samples) || current.time > samples[end].time)
        push!(samples,current)
    end
    segments = NamedTuple{(:a,:b,:category),Tuple{NTuple{2,Float64},NTuple{2,Float64},Symbol}}[]
    for i in 1:length(samples)-1
        a,b = samples[i],samples[i+1]
        abs(b.lon-a.lon) > 180 && continue
        push!(segments,(a=(a.lon,a.lat),b=(b.lon,b.lat),category=storm_class(a.kind,a.wind_knots)))
    end
    segments
end
end
