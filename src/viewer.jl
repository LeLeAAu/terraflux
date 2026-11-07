module TerraFluxViewer
include("data.jl")
include("globe.jl")
include("live.jl")
include("storms.jl")
include("detection.jl")
using .TerraFluxDetection
include("ui_scope.jl")
using .TerraFluxUIScope
include("storm_icons.jl")
include("tracker.jl")
using .TerraFluxTracker
using .TerraFluxLive
using .TerraFluxGlobe
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

function build_viewer(d::WeatherData; session_root=joinpath(@__DIR__,"..","sessions"),
        icon_style_path=joinpath(@__DIR__,"..","assets","storm_tracker","style.toml"))
    set_theme!(theme_dark(); fontsize=15, backgroundcolor=BG, textcolor=INK,
        Axis=(backgroundcolor=PANEL, xgridcolor=(:white, 0.08), ygridcolor=(:white, 0.08)))
    fig = Figure(size=(1440, 860), figure_padding=26)
    header = GridLayout(fig[1, 1:2])
    Label(header[1, 1], "TERRAFLUX", fontsize=30, font=:bold, color=ACCENT, halign=:left, tellwidth=false)
    Label(header[2, 1], "PHÒNG QUAN SÁT KHÍ QUYỂN", color=MUTED, fontsize=13, halign=:left, tellwidth=false)
    viewmenu = Menu(header[1, 2], options=[("Bản đồ 2D", :map), ("Địa cầu 3D", :globe), ("Storm Tracker", :tracker)], default=1, width=235, halign=:right)
    resetview = Button(header[2, 2], label="Đặt lại góc nhìn", width=235, halign=:right, buttoncolor=PANEL, labelcolor=INK)
    colsize!(header, 1, Relative(0.7))
    physical_widgets = Any[]
    sidebar = GridLayout(fig[2, 1], width=285, tellheight=false)
    push!(physical_widgets, Label(sidebar[1, 1], "01   TRƯỜNG QUAN SÁT", color=MUTED, fontsize=12, halign=:left))
    fieldmenu = Menu(sidebar[2, 1], options=[(field_label(f), f) for f in FIELDS], default=1, width=280)
    push!(physical_widgets, Label(sidebar[3, 1], "02   TẦNG KHÍ QUYỂN", color=MUTED, fontsize=12, halign=:left))
    layermenu = Menu(sidebar[4, 1], options=[(layer_label(d, k), k) for k in eachindex(d.layers)],
        default=length(d.layers), width=280)
    push!(physical_widgets, Label(sidebar[5, 1], "σ gần 1: gần bề mặt\nσ gần 0: tầng cao\nKhông phải độ cao cố định.", color=MUTED, fontsize=13, halign=:left, justification=:left))
    lockrow = GridLayout(sidebar[6, 1])
    lockscale = Checkbox(lockrow[1, 1], checked=true)
    push!(physical_widgets, Label(lockrow[1, 2], "Giữ thang màu theo thời gian", fontsize=13, halign=:left))
    push!(physical_widgets, Label(sidebar[7, 1], "03   ĐIỂM THEO DÕI", color=MUTED, fontsize=12, halign=:left))
    pointtext = Observable("Bấm vào bản đồ để chọn điểm.\nGiá trị tại ô lưới gần nhất.")
    push!(physical_widgets, Label(sidebar[8, 1], pointtext, fontsize=14, halign=:left, justification=:left))
    stattext = Observable("")
    push!(physical_widgets, Label(sidebar[9, 1], stattext, fontsize=13, color=MUTED, halign=:left, justification=:left))
    gridtext = Observable("Lưới đầu ra: $(length(d.lon)) × $(length(d.lat))\n$(length(d.layers)) tầng · $(length(d.times)) thời điểm\nPhóng to không tăng độ phân giải.")
    push!(physical_widgets, Label(sidebar[10, 1], gridtext, fontsize=12, color=MUTED, halign=:left, justification=:left))
    append!(physical_widgets,[fieldmenu,layermenu,lockscale])
    scope_widget_inputs!(physical_widgets)
    rowgap!(sidebar, 12)
    maparea = GridLayout(fig[2, 2])
    title = Observable("")
    Label(maparea[1, 1:2], title, font=:bold, fontsize=16)
    ax = Axis(maparea[2, 1], xlabel="Kinh độ", ylabel="Vĩ độ", aspect=DataAspect(),
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
    colorbar = Colorbar(maparea[2, 2], heat, label=unittext, width=16)
    helptext = Observable("Bản đồ 2D • Cuộn: thu phóng • Chuột phải: di chuyển • Bấm trái: đọc giá trị")
    Label(maparea[3, 1:2], helptext, fontsize=11, color=MUTED)
    globe = LScene(maparea[2, 1]; show_axis=false)
    cam3d!(globe.scene; center=false, fixed_axis=true, zoom_shift_lookat=false,
        translation_button=false, reposition_button=false, up_key=false, down_key=false,
        left_key=false, right_key=false, forward_key=false, backward_key=false,
        increase_fov_key=false, decrease_fov_key=false, clipping_mode=:static, near=0.01, far=100.0)
    # Keep the camera outside the globe, including after repeated wheel/keyboard zooms.
    camera3d = cameracontrols(globe.scene)
    correcting_camera = Ref(false)
    on(camera3d.eyeposition) do eye
        correcting_camera[] && return
        distance = sqrt(sum(abs2, eye))
        if !isfinite(distance) || distance < 1.2 || distance > 12
            correcting_camera[] = true
            try
                direction = isfinite(distance) && distance > 0 ? eye/distance : Vec3d(sphere_point(105,20))
                radius = isfinite(distance) ? clamp(distance,1.2,12) : 3.5
                camera3d.eyeposition[] = direction*radius
            finally
                correcting_camera[] = false
            end
        end
    end
    points, faces = globe_geometry(d.lon, d.lat)
    vertexcolors = Observable(globe_colors(frame(d, :temp, layer[], time[])))
    mesh!(globe, Point3f.(points), [Makie.GeometryBasics.TriangleFace(f...) for f in faces];
        color=vertexcolors, colormap=cmap, colorrange=limits, shading=NoShading,
        nan_color=:transparent)
    coastpoints = Makie.convert_arguments(Lines, GeoMakie.coastlines())[1]
    lines!(globe, [Point3f(sphere_point(p[1],p[2];radius=1.003)) for p in coastpoints];
        color=(:white,0.7), linewidth=0.8)
    graticule = Point3f[]
    for lat in -60:30:60
        append!(graticule, [Point3f(sphere_point(lon,lat;radius=1.002)) for lon in -180:2:180])
        push!(graticule, Point3f(NaN))
    end
    for lon in -180:30:150
        append!(graticule, [Point3f(sphere_point(lon,lat;radius=1.002)) for lat in -90:2:90])
        push!(graticule, Point3f(NaN))
    end
    lines!(globe, graticule; color=(:white,0.15), linewidth=0.6)
    globe_marker = Observable(Point3f[])
    scatter!(globe, globe_marker; color=ACCENT, markersize=14, strokecolor=:black, strokewidth=2)
    reset_globe() = update_cam!(globe.scene, Vec3f(sphere_point(105,20;radius=3.5)), Vec3f(0), Vec3f(0,0,1))
    reset_globe()
    on(resetview.clicks) do _
        limits!(ax, -180, 180, -90, 90)
        reset_globe()
        tracker.reset!()
    end
    livepanel = GridLayout(fig[3, 1:2])
    livestatus = Observable("MÔ PHỎNG MỚI / T32 · 8 tầng · tối đa 10 ngày · mỗi bước 6 giờ")
    Label(livepanel[1,1:7],livestatus;fontsize=12,color=ACCENT,halign=:left,tellwidth=false)
    sourcemenu = Menu(livepanel[2,1],options=[("Tệp đã mở",:file),("Phiên mô phỏng",:live)],default=1,width=170)
    newrun = Button(livepanel[2,2],label="Phiên mới",buttoncolor=PANEL,labelcolor=INK)
    runmodel = Button(livepanel[2,3],label="Chạy",buttoncolor=PANEL,labelcolor=INK)
    pausemodel = Button(livepanel[2,4],label="Tạm dừng",buttoncolor=PANEL,labelcolor=INK)
    stepmodel = Button(livepanel[2,5],label="+6 giờ",buttoncolor=PANEL,labelcolor=INK)
    stopmodel = Button(livepanel[2,6],label="Kết thúc",buttoncolor=PANEL,labelcolor=INK)
    Label(livepanel[2,7],"Độc lập với phát lại",fontsize=12,color=MUTED)
    timeline = GridLayout(fig[4, 1:2])
    clocktext = Observable("")
    Label(timeline[1, 1:4], clocktext, fontsize=17, font=:bold, halign=:left)
    back = Button(timeline[2, 1], label="◀", width=50, buttoncolor=PANEL, labelcolor=INK)
    play = Button(timeline[2, 2], label="Phát", width=95, buttoncolor=PANEL, labelcolor=INK)
    forward = Button(timeline[2, 3], label="▶", width=50, buttoncolor=PANEL, labelcolor=INK)
    slider = Slider(timeline[2, 4], range=1:length(d.times), startvalue=1)
    sourceinfo = Observable("Phát lại: 2 khung/giây · Tệp đã mở · $(basename(d.path))")
    Label(timeline[3, 1:4],sourceinfo,fontsize=12,color=MUTED,halign=:left)
    rowsize!(fig.layout, 1, Fixed(88))
    colsize!(fig.layout, 1, Fixed(285))
    colgap!(fig.layout, 28)
    rowgap!(fig.layout, 24)
    playing = Observable(false)
    analyzed_data=Ref{Any}(nothing)
    analysis_task=Ref{Any}(nothing)
    function model_provider()
        if analysis_task[] === nothing || (istaskdone(analysis_task[]) && analyzed_data[] !== d)
            snapshot=d
            analyzed_data[]=snapshot
            analysis_task[]=Threads.@spawn begin
                try
                    detect_tracks(snapshot)
                catch err
                    sprint(showerror,err)
                end
            end
        end
        istaskdone(analysis_task[]) && analyzed_data[] === d ? fetch(analysis_task[]) : nothing
    end
    tracker = build_tracker(fig[2,1],maparea[2,1:2],d.times[time[]];icon_style_path,model_provider,
        on_physical=(location,as_globe) -> begin
            selected[] = nearest_cell(d,location...)
            viewmenu.i_selected[] = as_globe ? 2 : 1
            if as_globe
                update_cam!(globe.scene,Vec3f(sphere_point(location...;radius=3.5)),Vec3f(0),Vec3f(0,0,1))
            end
        end,
        on_start=timestamp -> set_close_to!(slider,argmin(abs.(d.times .- timestamp))))
    on(viewmenu.selection) do mode
        is_globe = mode == :globe
        is_tracker = mode == :tracker
        ax.blockscene.visible[] = mode == :map
        ax.scene.visible[] = mode == :map
        globe.blockscene.visible[] = is_globe
        globe.scene.visible[] = is_globe
        colorbar.blockscene.visible[] = !is_tracker
        for widget in physical_widgets; widget.blockscene.visible[] = !is_tracker; end
        tracker.set_active!(is_tracker)
        helptext[] = is_tracker ? "Chọn nguồn trong Storm Tracker • Biểu tượng là vị trí đại diện, không chỉ bán kính gió" :
            is_globe ? "Địa cầu 3D • Kéo chuột trái: xoay • Cuộn: thu phóng • Bấm trái: đọc giá trị" :
            "Bản đồ 2D • Cuộn: thu phóng • Chuột phải: di chuyển • Bấm trái: đọc giá trị"
        refresh()
    end
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
        vertexcolors[] = globe_colors(a)
        cmap[] = colormap_for(f)
        unittext[] = field_unit(f)
        if rescale || !lockscale.checked[]
            limits[] = color_limits(d, f, k, t; locked=lockscale.checked[])
        end
        description = f == :mslp ? "Quy về mực biển · Không phụ thuộc tầng chọn" : layer_label(d, k)
        title[] = "$(field_label(f)) / $(field_unit(f))\n$description"
        clocktext[] = "$(Dates.format(d.times[t], dateformat"yyyy-mm-dd HH:MM"))   ·   Khung $t / $(length(d.times))"
        finite = filter(isfinite, vec(a))
        stattext[] = isempty(finite) ? (f == :mslp && sourcemenu.selection[] == :live && t == 1 ? "Áp suất mốc khởi tạo\nchưa được mô hình tính." : "Khung này thiếu dữ liệu.") : @sprintf("Toàn bản đồ / %s\nMin  %.3f\nMax  %.3f", field_unit(f), minimum(finite), maximum(finite))
        refresh_point()
        tracker.clock[] = d.times[t]
        if viewmenu.selection[] == :tracker
            title[] = tracker.title[]
        end
    end
    on(tracker.title) do text
        viewmenu.selection[] == :tracker && (title[]=text)
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
        globe_marker[] = selected[] === nothing ? Point3f[] :
            [Point3f(sphere_point(d.lon[selected[][1]], d.lat[selected[][2]]; radius=1.01))]
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
    pressed = Ref{Union{Nothing,Tuple{Float64,Float64}}}(nothing)
    on(events(globe.scene).mousebutton, priority=3) do event
        if viewmenu.selection[] == :globe && event.button == Mouse.left
            if event.action == Mouse.press && is_mouseinside(globe.scene)
                pressed[] = Tuple(Float64.(events(fig).mouseposition[]))
            elseif event.action == Mouse.release
                start = pressed[]
                pressed[] = nothing
                pixel = events(fig).mouseposition[]
                if start !== nothing && is_mouseinside(globe.scene) && sum((pixel[i]-start[i])^2 for i in 1:2) <= 16
                    ray = Makie.ray_at_cursor(globe.scene)
                    hit = sphere_hit(ray.origin, ray.direction)
                    hit !== nothing && (selected[] = nearest_cell(d, hit...))
                end
            end
        end
        Consume(false)
    end
    original = d
    session = Ref{Union{Nothing,LiveSession}}(nothing)
    history = Ref{Union{Nothing,WeatherData}}(nothing)
    imported = Ref(0)
    function replace_data!(next)
        (next.lon == original.lon && next.lat == original.lat && next.layers == original.layers) ||
            error("Phiên trực tiếp hiện yêu cầu cùng lưới T32/8 tầng với dữ liệu đang mở.")
        d = next
        playing[] = false
        time[] = length(d.times)
        slider.range[] = 1:length(d.times)
        set_close_to!(slider,length(d.times))
        gridtext[] = "Lưới đầu ra: $(length(d.lon)) × $(length(d.lat))\n$(length(d.layers)) tầng · $(length(d.times)) thời điểm\nPhóng to không tăng độ phân giải."
        sourceinfo[] = sourcemenu.selection[] == :live ? "PHÁT LẠI / phiên mới · 2 khung/giây · $(basename(session[].directory))" :
            "PHÁT LẠI / tệp đã mở · 2 khung/giây · $(basename(original.path))"
        refresh()
    end
    on(sourcemenu.selection) do source
        if source == :file
            replace_data!(original)
        elseif history[] !== nothing
            replace_data!(history[])
        else
            livestatus[] = "Phiên chưa có đầu ra. Bấm Chạy hoặc +6 giờ; bản đồ vẫn đang hiển thị tệp đã mở."
        end
    end
    function poll_live!()
        session[] === nothing && return
        status = read_status(session[])
        for path in status["files"][imported[]+1:end]
            chunk = load_live_chunk(path;initial=imported[] == 0)
            history[] = history[] === nothing ? chunk : append_weather(history[],chunk)
            imported[] += 1
        end
        if sourcemenu.selection[] == :live && history[] !== nothing && d !== history[]
            replace_data!(history[])
        end
        state = status["state"]
        text = Dict("starting"=>"Đang khởi tạo (lần đầu có thể mất vài phút)",
            "paused"=>"Đã tạm dừng", "running"=>"Đang chạy", "stepping"=>"Đang tính một bước 6 giờ",
            "complete"=>"Đã hoàn tất 10 ngày", "stopped"=>"Đã kết thúc", "error"=>"Lỗi mô phỏng")
        message = get(text,state,state)
        pending = get(status,"sequence",0) < session[].sequence
        pending && (message *= " · lệnh đang chờ mốc 6 giờ")
        state == "error" && (message *= " · " * first(get(status,"error","Xem worker.log"),180))
        livestatus[] = "$message · Đã tính $(status["completed"]*6) giờ · $(basename(session[].directory))"
        status
    end
    on(newrun.clicks) do _
        try
            if session[] !== nothing && process_running(session[].process)
                livestatus[] = "Phiên hiện tại còn hoạt động. Bấm Kết thúc trước khi tạo phiên mới."
            elseif (length(original.lon),length(original.lat),length(original.layers)) != (96,48,8)
                livestatus[] = "Hãy mở dữ liệu mẫu T32/8 tầng để tạo phiên mô phỏng trực tiếp."
            else
                session[] = start_session(;root=session_root)
                history[] = nothing
                imported[] = 0
                sourcemenu.i_selected[] = 2
                poll_live!()
            end
        catch err
            livestatus[] = first(sprint(showerror,err),220)
        end
    end
    function request_model(action)
        try
            session[] === nothing && error("Bấm Phiên mới trước.")
            status = read_status(session[])
            if action == "step" && (status["state"] != "paused" || get(status,"sequence",0) < session[].sequence)
                livestatus[] = "Bước +6 giờ chỉ dùng sau khi phiên đã tạm dừng và xử lý xong lệnh trước."
                return
            end
            action in ("run","step") && (sourcemenu.i_selected[] = 2)
            send_command!(session[],action)
            poll_live!()
        catch err
            livestatus[] = first(sprint(showerror,err),220)
        end
    end
    on(runmodel.clicks) do _; request_model("run"); end
    on(pausemodel.clicks) do _; request_model("pause"); end
    on(stepmodel.clicks) do _; request_model("step"); end
    on(stopmodel.clicks) do _; request_model("stop"); end
    refresh()
    notify(viewmenu.selection)
    (; fig, ax, globe, tracker, session, history, sourcemenu, newrun, runmodel, pausemodel, stepmodel, stopmodel,
        livestatus, poll_live!, replace_data!, viewmenu, resetview, vertexcolors, globe_marker, fieldmenu, layermenu, lockscale, slider, selected, field, layer, time,
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

function launch(path)
    GLMakie.activate!()
    data = load_weather(path)
    viewer = build_viewer(data)
    screen = display(viewer.fig)
    # Data polling/playback keep their original cadence regardless of icon style FPS.
    ticker = @async begin
        tick=0
        while isopen(screen)
            sleep(0.25)
            isopen(screen) || break
            try
                viewer.poll_live!()
                viewer.tracker.poll_model!()
            catch err
                viewer.livestatus[] = "Không đọc được phiên: " * first(sprint(showerror,err),180)
            end
            tick+=1
            iseven(tick) && advance_playback!(viewer)
        end
    end
    animator = @async begin
        started=time_ns()
        while isopen(screen)
            sleep(1/viewer.tracker.style.refresh_fps)
            isopen(screen) || break
            viewer.tracker.animate!(Float64(time_ns()-started)/1e9)
        end
    end
    try
        wait(screen)
    finally
        viewer.session[] !== nothing && stop_session!(viewer.session[])
        wait(ticker)
        wait(animator)
    end
    viewer
end
end
