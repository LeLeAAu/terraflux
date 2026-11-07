module TerraFluxStormIcons
using GLMakie, TOML
export IconStyle, load_icon_style, procedural_marker, icon_sprite, icon_frame, icon_rotation

struct SpriteStyle
    frames::Vector{Matrix{RGBAf}}
    fps::Float64
    rotate::Bool
end
struct IconStyle
    size::Float32
    selected_size::Float32
    glow_opacity::Float32
    glow_scale::Float32
    show_symbol_on_sprite::Bool
    arms::Int
    inner_radius::Float64
    twist::Float64
    spin::Float64
    refresh_fps::Float64
    sprites::Dict{Symbol,SpriteStyle}
end
function checked_number(table,key,default,low,high)
    value=Float64(get(table,key,default))
    isfinite(value) && low <= value <= high || error("Thiết lập icon '$key' phải nằm trong $low…$high.")
    value
end

function load_icon_style(path=joinpath(@__DIR__,"..","assets","storm_tracker","style.toml"))
    config=TOML.parsefile(path)
    appearance=get(config,"appearance",Dict())
    procedural=get(config,"procedural",Dict())
    animation=get(config,"animation",Dict())
    sprites=Dict{Symbol,SpriteStyle}()
    allowed=("default","LOW","L","D","SD","S","SS","EX","POST","RL","UNKNOWN","C1","C2","C3","C4","C5","MODEL_LOW")
    for (category,input) in get(config,"sprites",Dict())
        category in allowed || error("Loại icon không hỗ trợ: $category")
        filename=get(input,"file","")
        isempty(filename) && continue
        source=normpath(joinpath(dirname(abspath(path)),filename))
        isfile(source) || error("Không tìm thấy ảnh icon: $source")
        lowercase(splitext(source)[2]) == ".png" || error("Icon phải là PNG: $source")
        frames=Int(get(input,"frames",1))
        1 <= frames <= 120 || error("Số khung PNG phải từ 1 tới 120.")
        fps=checked_number(input,"fps",8,0.1,60)
        image=RGBAf.(Makie.FileIO.load(source))
        ndims(image) == 2 || error("Ảnh icon phải là ảnh 2D.")
        height,width=size(image)
        height > 0 && width >= frames && width % frames == 0 || error("Chiều rộng PNG phải chia hết cho số khung.")
        frame_width=width÷frames
        tiles=[Matrix(image[:,(i-1)*frame_width+1:i*frame_width]) for i in 1:frames]
        sprites[Symbol(category)]=SpriteStyle(tiles,fps,get(input,"rotate",false))
    end
    style=IconStyle(
        Float32(checked_number(appearance,"size",58,16,256)),
        Float32(checked_number(appearance,"selected_size",70,16,256)),
        Float32(checked_number(appearance,"glow_opacity",0.16,0,1)),
        Float32(checked_number(appearance,"glow_scale",1.12,1,3)),
        get(appearance,"show_symbol_on_sprite",false),
        Int(get(procedural,"arms",3)),
        checked_number(procedural,"inner_radius",0.24,0.05,0.9),
        checked_number(procedural,"twist",1.6,-6,6),
        checked_number(animation,"spin_radians_per_second",0.32,0,10),
        checked_number(animation,"refresh_fps",30,1,60),sprites
    )
    1 <= style.arms <= 8 || error("Số cánh icon phải từ 1 tới 8.")
    style
end

# CUSTOM DRAWING ENTRY POINT: replace this function for a different procedural icon.
# Keep its normalized coordinates in roughly -0.5…0.5 so size remains screen pixels.
function procedural_marker(style::IconStyle)
    points=Point2f[]
    middle=(1+style.inner_radius)/2
    amplitude=(1-style.inner_radius)/2
    for angle in range(0,2pi;length=181)[1:end-1]
        radius=middle+amplitude*cos(style.arms*angle)
        theta=angle+style.twist*(1-radius)
        push!(points,Point2f(0.5radius*cos(theta),0.5radius*sin(theta)))
    end
    Makie.GeometryBasics.Polygon(points)
end
icon_sprite(style,category)=category == :MODEL_LOW ? get(style.sprites,:MODEL_LOW,nothing) : get(style.sprites,category,get(style.sprites,:default,nothing))
function icon_frame(sprite,seconds;reduced=false)
    index=reduced ? 1 : 1+mod(floor(Int,max(0,seconds)*sprite.fps),length(sprite.frames))
    sprite.frames[index]
end
function icon_rotation(style,latitude,seconds;reduced=false,sprite=nothing)
    reduced && return 0f0
    sprite !== nothing && !sprite.rotate && return 0f0
    Float32((latitude >= 0 ? 1 : -1)*max(0,seconds)*style.spin)
end
end
