module TerraFluxWeatherStyle
using GLMakie,TOML
using ..TerraFluxData
export load_weather_style, weather_palette, display_frame, display_unit, weather_limits

function load_weather_style(path=joinpath(@__DIR__,"..","assets","weather","style.toml"))
    style=TOML.parsefile(path)
    for key in ("temperature","wind","humidity","pressure")
        input=style[key]
        length(input["range"])==2 && all(isfinite,input["range"]) && input["range"][1]<input["range"][2] || error("Thang $key không hợp lệ.")
        length(input["colors"])>=2 || error("Bảng màu $key quá ít màu.")
        parse.(RGBAf,input["colors"])
    end
    p=style["particles"]
    p["count"] isa Integer && p["trail_steps"] isa Integer &&
        20<=p["count"]<=5000 && 2<=p["trail_steps"]<=40 || error("Số hạt/độ dài vệt không hợp lệ.")
    all(x->isfinite(x) && x>0,(p["lifetime_seconds"],p["visual_seconds_per_second"])) || error("Tốc độ/tuổi hạt không hợp lệ.")
    1<=style["pressure"]["isobar_interval_hpa"]<=20 || error("Khoảng đẳng áp không hợp lệ.")
    style
end
style_key(f)=get(Dict(:temp=>"temperature",:sst=>"temperature",:lst=>"temperature",:wind=>"wind",:rh=>"humidity",:mslp=>"pressure"),f,nothing)
function weather_palette(style,f)
    key=style_key(f)
    key===nothing && return f in (:u,:v) ? Makie.to_colormap(:balance) : Makie.to_colormap(:haline)
    anchors=parse.(RGBAf,style[key]["colors"])
    [begin
        at=1+x*(length(anchors)-1)
        i=min(floor(Int,at),length(anchors)-1)
        Float32(1-(at-i))*anchors[i]+Float32(at-i)*anchors[i+1]
    end for x in range(0,1;length=256)]
end
display_unit(f)=f==:wind ? "km/h" : field_unit(f)
display_frame(d,f,k,t)=f==:wind ? frame(d,f,k,t).*3.6f0 : frame(d,f,k,t)
function weather_limits(style,d,f,k,t;standard=true,locked=true)
    key=style_key(f)
    standard && key!==nothing && return Tuple(Float32.(style[key]["range"]))
    lo,hi=color_limits(d,f,k,t;locked)
    f==:wind ? (3.6f0lo,3.6f0hi) : (lo,hi)
end
end
