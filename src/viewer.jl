module TerraFluxViewer
include("data.jl")
using .TerraFluxData
using GLMakie
using GeoMakie
using Dates, Printf
export build_viewer, launch

const BG = colorant"#101722"
const PANEL = colorant"#192332"
const INK = colorant"#e8eef5"
const MUTED = colorant"#a6b7c8"
const ACCENT = colorant"#66ded0"
colormap_for(f) = f in (:u, :v) ? :balance : f == :humid ? :haline : f == :mslp ? :viridis : f == :wind ? :speed : :thermal

function build_viewer(d::WeatherData)
    set_theme!(theme_dark(); fontsize=15, backgroundcolor=BG, textcolor=INK,
        Axis=(backgroundcolor=PANEL, xgridcolor=(:white, 0.08), ygridcolor=(:white, 0.08)))
    fig = Figure(size=(1440, 860), figure_padding=26)
    header = GridLayout(fig[1, 1:2])
    Label(header[1, 1], "TERRAFLUX", fontsize=30, font=:bold, color=ACCENT, halign=:left, tellwidth=false)
    Label(header[2, 1], "PHÒNG QUAN SÁT KHÍ QUYỂN", color=MUTED, fontsize=13, halign=:left, tellwidth=false)
    Label(header[1:2, 2], "V1 / PHÁT LẠI DỮ LIỆU", color=ACCENT, fontsize=13, halign=:right, tellwidth=false)
    colsize!(header, 1, Relative(0.7))
    sidebar = GridLayout(fig[2, 1], width=285, tellheight=false)
    Label(sidebar[1, 1], "01   TRƯỜNG QUAN SÁT", color=MUTED, fontsize=12, halign=:left)
    fieldmenu = Menu(sidebar[2, 1], options=[(field_label(f), f) for f in FIELDS], default=1, width=280)
    Label(sidebar[3, 1], "02   TẦNG KHÍ QUYỂN", color=MUTED, fontsize=12, halign=:left)
    layermenu = Menu(sidebar[4, 1], options=[(layer_label(d, k), k) for k in eachindex(d.layers)],
        default=length(d.layers), width=280)
    Label(sidebar[5, 1], "σ gần 1: gần bề mặt\nσ gần 0: tầng cao\nKhông phải độ cao cố định.", color=MUTED, fontsize=13, halign=:left, justification=:left)
    lockrow = GridLayout(sidebar[6, 1])
    lockscale = Checkbox(lockrow[1, 1], checked=true)
    Label(lockrow[1, 2], "Giữ thang màu theo thời gian", fontsize=13, halign=:left)
    Label(sidebar[7, 1], "03   ĐIỂM THEO DÕI", color=MUTED, fontsize=12, halign=:left)
    pointtext = Observable("Bấm vào bản đồ để chọn điểm.\nGiá trị tại ô lưới gần nhất.")
    Label(sidebar[8, 1], pointtext, fontsize=14, halign=:left, justification=:left)
    stattext = Observable("")
    Label(sidebar[9, 1], stattext, fontsize=13, color=MUTED, halign=:left, justification=:left)
    Label(sidebar[10, 1], "Lưới đầu ra: $(length(d.lon)) × $(length(d.lat))\n$(length(d.layers)) tầng · $(length(d.times)) thời điểm\nPhóng to không tăng độ phân giải.", fontsize=12, color=MUTED, halign=:left, justification=:left)
    rowgap!(sidebar, 18)
    maparea = GridLayout(fig[2, 2])
    title = Observable("")
    ax = Axis(maparea[1, 1], title=title, xlabel="Kinh độ", ylabel="Vĩ độ", aspect=DataAspect(),
        xticks=(-180:60:180), yticks=(-90:30:90))
    limits!(ax, -180, 180, -90, 90)
    field = Observable(:temp)
    layer = Observable(length(d.layers))
    time = Observable(1)
    selected = Observable{Union{Nothing,Tuple{Int,Int}}}(nothing)
    limits = Observable(color_limits(d, :temp, layer[], 1))
    mapvalues = Observable(vcat(frame(d, :temp, layer[], 1), frame(d, :temp, layer[], 1)[1:1, :]))
    cmap = Observable(colormap_for(:temp))
    heat = heatmap!(ax, vcat(d.lon, d.lon[1]+360), d.lat, mapvalues;
        colorrange=limits, colormap=cmap, nan_color=:transparent, interpolate=false)
    lines!(ax, GeoMakie.coastlines(); color=(:white, 0.65), linewidth=0.8, xautolimits=false, yautolimits=false)
    marker = Observable(Point2f[])
    scatter!(ax, marker; markersize=14, color=ACCENT, strokecolor=:black, strokewidth=2)
    unittext = Observable("°C")
    Colorbar(maparea[1, 2], heat, label=unittext, width=16)
    Label(maparea[2, 1:2], "Bản đồ kinh–vĩ độ  •  Đường bờ: Natural Earth / GeoMakie  •  Cuộn: thu phóng  •  Chuột phải: di chuyển  •  Ctrl + bấm: đặt lại",
        fontsize=11, color=MUTED)
    timeline = GridLayout(fig[3, 1:2])
    clocktext = Observable("")
    Label(timeline[1, 1:4], clocktext, fontsize=17, font=:bold, halign=:left)
    back = Button(timeline[2, 1], label="◀", width=50, buttoncolor=PANEL, labelcolor=INK)
    play = Button(timeline[2, 2], label="Phát", width=95, buttoncolor=PANEL, labelcolor=INK)
    forward = Button(timeline[2, 3], label="▶", width=50, buttoncolor=PANEL, labelcolor=INK)
    slider = Slider(timeline[2, 4], range=1:length(d.times), startvalue=1)
    Label(timeline[3, 1:4], "Phát lại: 2 khung/giây · Không chạy thêm mô phỏng · $(basename(d.path))", fontsize=12, color=MUTED, halign=:left)
    rowsize!(fig.layout, 1, Fixed(88))
    colsize!(fig.layout, 1, Fixed(285))
    colgap!(fig.layout, 28)
    rowgap!(fig.layout, 24)
    playing = Observable(false)
    function refresh_point()
        cell = selected[]
        if cell !== nothing
            i, j = cell
            value = frame(d, field[], layer[], time[])[i, j]
            val = isfinite(value) ? @sprintf("%.3f", value) : "Thiếu dữ liệu"
            pointtext[] = @sprintf("Ô lưới: %.2f° / %.2f°\n%s %s", d.lon[i], d.lat[j], val, field_unit(field[]))
        end
    end
    function refresh(; rescale=true)
        f, k, t = field[], layer[], time[]
        a = frame(d, f, k, t)
        mapvalues[] = vcat(a, a[1:1, :])
        cmap[] = colormap_for(f)
        unittext[] = field_unit(f)
        if rescale || !lockscale.checked[]
            limits[] = color_limits(d, f, k, t; locked=lockscale.checked[])
        end
        description = f == :mslp ? "Quy về mực biển · Không phụ thuộc tầng chọn" : layer_label(d, k)
        title[] = "$(field_label(f)) / $(field_unit(f))\n$description"
        clocktext[] = "$(Dates.format(d.times[t], dateformat"yyyy-mm-dd HH:MM"))   ·   Khung $t / $(length(d.times))"
        finite = filter(isfinite, vec(a))
        stattext[] = isempty(finite) ? "Khung này thiếu dữ liệu." : @sprintf("Toàn bản đồ / %s\nMin  %.3f\nMax  %.3f", field_unit(f), minimum(finite), maximum(finite))
        refresh_point()
    end
    on(fieldmenu.selection) do f
        field[] = f
        refresh()
    end
    on(layermenu.selection) do k
        layer[] = k
        refresh()
    end
    on(lockscale.checked) do _
        refresh()
    end
    on(slider.value) do t
        time[] = round(Int, t)
        refresh(; rescale=false)
    end
    on(selected) do _
        marker[] = selected[] === nothing ? Point2f[] : [Point2f(d.lon[selected[][1]], d.lat[selected[][2]])]
        refresh_point()
    end
    step(delta) = set_close_to!(slider, clamp(time[] + delta, 1, length(d.times)))
    on(back.clicks) do _; step(-1); end
    on(forward.clicks) do _; step(1); end
    on(play.clicks) do _
        playing[] = !playing[]
    end
    on(playing) do active; play.label[] = active ? "Dừng" : "Phát"; end
    on(events(ax).mousebutton, priority=2) do event
        if event.button == Mouse.left && event.action == Mouse.press && is_mouseinside(ax.scene) &&
                !ispressed(fig, Keyboard.left_control) && !ispressed(fig, Keyboard.right_control)
            x, y = mouseposition(ax)
            if -180 <= x <= 180 && -90 <= y <= 90
                selected[] = nearest_cell(d, x, y)
            end
        end
        Consume(false)
    end
    refresh()
    (; fig, ax, fieldmenu, layermenu, lockscale, slider, selected, field, layer, time,
        pointtext, mapvalues, limits, play, back, forward, playing)
end

function advance_playback!(viewer)
    viewer.playing[] || return
    if viewer.time[] < length(viewer.slider.range[])
        set_close_to!(viewer.slider, viewer.time[] + 1)
    else
        viewer.playing[] = false
    end
end

function launch(path; smoke=false, screenshot=nothing)
    GLMakie.activate!()
    data = load_weather(path)
    viewer = build_viewer(data)
    screen = display(viewer.fig)
    if smoke
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
        close(screen)
        println("VIEWER_SMOKE_PASSED")
        return viewer
    end
    @async begin
        while isopen(screen)
            sleep(0.5)
            isopen(screen) || break
            advance_playback!(viewer)
        end
    end
    wait(screen)
    viewer
end
end
