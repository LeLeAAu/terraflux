# Requires a display/OpenGL. Exercises callbacks and renders both views.
using GLMakie, Test
include(joinpath(@__DIR__, "..", "src", "viewer.jl"))
using .TerraFluxViewer
using .TerraFluxViewer.TerraFluxData
using .TerraFluxViewer.TerraFluxGlobe
using .TerraFluxViewer: advance_playback!
path = joinpath(@__DIR__, "..", "run_0001", "output.nc")
screenshot = isempty(ARGS) ? nothing : abspath(first(ARGS))
GLMakie.activate!()
data = load_weather(path)
viewer = build_viewer(data)
screen = display(viewer.fig)
try
    # Exercise the same observable callbacks as the controls, then render a frame.
    for f in FIELDS
        viewer.fieldmenu.i_selected[] = findfirst(==(f), FIELDS)
        viewer.layermenu.i_selected[] = 1
        set_close_to!(viewer.slider, length(viewer.slider.range[]))
        viewer.selected[] = (1, 1)
        @assert occursin(field_unit(f), viewer.pointtext[])
        @assert viewer.mapvalues[][1:end-1, :] == frame(data, f, 1, length(data.times))
    end
    viewer.fieldmenu.i_selected[] = 1
    viewer.layermenu.i_selected[] = length(data.layers)
    viewer.lockscale.checked[] = false
    set_close_to!(viewer.slider, min(20, length(data.times)))
    viewer.play.clicks[] += 1
    @assert viewer.playing[]
    previous = viewer.time[]
    advance_playback!(viewer)
    @assert viewer.time[] == min(previous+1, length(data.times))
    viewer.play.clicks[] += 1
    @assert !viewer.playing[]
    viewer.back.clicks[] += 1
    @assert viewer.time[] == previous
    viewer.forward.clicks[] += 1
    @assert viewer.time[] == min(previous+1, length(data.times))
    set_close_to!(viewer.slider, length(data.times))
    viewer.playing[] = true
    advance_playback!(viewer)
    @assert !viewer.playing[]
    viewer.lockscale.checked[] = true
    set_close_to!(viewer.slider, min(20, length(data.times)))
    before = viewer.limits[]
    set_close_to!(viewer.slider, 1)
    @assert viewer.limits[] == before
    set_close_to!(viewer.slider, min(20, length(data.times)))
    # Send real mouse events through the axis picking callback.
    viewport = viewer.ax.scene.viewport[]
    pixel = viewport.origin .+ viewport.widths .* (0.8, 0.62)
    viewer.selected[] = nothing
    events(viewer.fig).mouseposition[] = Tuple(pixel)
    events(viewer.fig).mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.press)
    events(viewer.fig).mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.release)
    @assert viewer.selected[] !== nothing
    @assert viewer.selected[] == nearest_cell(data, 108, 21.6)
    screenshot !== nothing && save(screenshot, viewer.fig)
    @testset "Linked globe controls and picking" begin
        selected = viewer.selected[]
        text = viewer.pointtext[]
        viewer.viewmenu.i_selected[] = 2
        @test viewer.globe.scene.visible[]
        @test !viewer.ax.scene.visible[]
        @test viewer.selected[] == selected
        @test viewer.pointtext[] == text
        for f in FIELDS
            viewer.fieldmenu.i_selected[] = findfirst(==(f), FIELDS)
            viewer.layermenu.i_selected[] = 1
            set_close_to!(viewer.slider, length(data.times))
            @test viewer.vertexcolors[] == globe_colors(frame(data,f,1,length(data.times)))
        end
        viewer.fieldmenu.i_selected[] = 1
        viewer.layermenu.i_selected[] = length(data.layers)
        set_close_to!(viewer.slider,min(20,length(data.times)))
        viewer.resetview.clicks[] += 1
        viewport = viewer.globe.scene.viewport[]
        center = Tuple(viewport.origin .+ viewport.widths ./ 2)
        events(viewer.fig).mouseposition[] = center
        events(viewer.fig).mousebutton[] = Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(viewer.fig).mousebutton[] = Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test viewer.selected[] == nearest_cell(data,105,20)
        camera = cameracontrols(viewer.globe.scene)
        eye = copy(camera.eyeposition[])
        # A real drag rotates the camera and must not select a new point.
        cell = viewer.selected[]
        events(viewer.fig).mousebutton[] = Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(viewer.fig).mouseposition[] = (center[1]+45,center[2]+10)
        events(viewer.fig).mousebutton[] = Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test viewer.selected[] == cell
        @test camera.eyeposition[] != eye
        olddistance = sum(abs2,camera.eyeposition[])
        events(viewer.fig).scroll[] = (0.,1.)
        @test sum(abs2,camera.eyeposition[]) != olddistance
        for delta in (100.,-100.)
            events(viewer.fig).scroll[] = (0.,delta)
            distance = sqrt(sum(abs2,camera.eyeposition[]))
            @test 1.2-1e-5 <= distance <= 12+1e-5
        end
        viewer.resetview.clicks[] += 1
        @test camera.eyeposition[] ≈ eye
        # Empty sky must not pick the far side or change the point.
        events(viewer.fig).mouseposition[] = Tuple(viewport.origin .+ (3,3))
        events(viewer.fig).mousebutton[] = Makie.MouseButtonEvent(Mouse.left,Mouse.press)
        events(viewer.fig).mousebutton[] = Makie.MouseButtonEvent(Mouse.left,Mouse.release)
        @test viewer.selected[] == cell
        if screenshot !== nothing
            base,extension = splitext(screenshot)
            save(base*"_globe"*extension,viewer.fig)
        end
        viewer.viewmenu.i_selected[] = 1
        @test viewer.ax.scene.visible[]
        @test !viewer.globe.scene.visible[]
        @test viewer.selected[] == cell
    end
    println("VIEWER_SMOKE_PASSED")
finally
    close(screen)
end
