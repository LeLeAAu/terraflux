using GLMakie, Test, TOML
include(joinpath(@__DIR__,"..","src","storm_icons.jl"))
using .TerraFluxStormIcons
@testset "Editable storm icon style and PNG frame selection" begin
    default=load_icon_style()
    @test default.size == 58
    @test default.selected_size == 70
    @test icon_sprite(default,:C3) === nothing
    @test icon_rotation(default,20,2) ≈ 0.64f0
    @test icon_rotation(default,-20,2) ≈ -0.64f0
    @test icon_rotation(default,20,2;reduced=true) == 0
    @test !isempty(procedural_marker(default).exterior)
    mktempdir() do dir
        # Two square transparent PNG frames, red then blue, left to right.
        image=fill(RGBAf(1,0,0,0.5),8,16)
        image[:,9:16] .= RGBAf(0,0,1,1)
        Makie.FileIO.save(joinpath(dir,"strip.png"),image)
        config=Dict("appearance"=>Dict("size"=>48.,"selected_size"=>64.),
            "animation"=>Dict("spin_radians_per_second"=>0.8,"refresh_fps"=>30.),
            "sprites"=>Dict("default"=>Dict("file"=>"strip.png","frames"=>2,"fps"=>8.,"rotate"=>false)))
        path=joinpath(dir,"style.toml")
        function write_config(data)
            open(path,"w") do io; TOML.print(io,data); end
        end
        write_config(config)
        style=load_icon_style(path)
        @test style.size == 48
        @test style.selected_size == 64
        sprite=icon_sprite(style,:C3)
        @test size(sprite.frames[1]) == (8,8)
        @test length(sprite.frames) == 2
        @test sprite.frames[1][1,1].alpha ≈ 128/255 atol=1e-5
        @test icon_frame(sprite,0) === sprite.frames[1]
        @test icon_frame(sprite,0.125) === sprite.frames[2]
        @test icon_frame(sprite,0.25) === sprite.frames[1]
        @test icon_frame(sprite,0.125;reduced=true) === sprite.frames[1]
        @test icon_rotation(style,20,2;sprite) == 0
        config["sprites"]["C3"]=Dict("file"=>"strip.png","frames"=>1,"fps"=>4.,"rotate"=>true)
        write_config(config)
        specialized=load_icon_style(path)
        @test length(icon_sprite(specialized,:C3).frames) == 1
        @test length(icon_sprite(specialized,:S).frames) == 2
        @test icon_rotation(specialized,20,2;sprite=icon_sprite(specialized,:C3)) ≈ 1.6f0
        invalid=deepcopy(config); invalid["sprites"]["default"]["frames"]=3
        write_config(invalid)
        @test_throws ErrorException load_icon_style(path)
        invalid=deepcopy(config); invalid["appearance"]["size"]=-1.
        write_config(invalid)
        @test_throws ErrorException load_icon_style(path)
        invalid=deepcopy(config); invalid["sprites"]["default"]["file"]="missing.png"
        write_config(invalid)
        @test_throws ErrorException load_icon_style(path)
    end
end
