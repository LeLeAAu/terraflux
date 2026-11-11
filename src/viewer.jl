module TerraFluxViewer
include("data.jl")
include("weather_style.jl")
include("wind_particles.jl")
using .TerraFluxWeatherStyle
using .TerraFluxWind
include("globe.jl")
include("live.jl")
include("storms.jl")
include("detection.jl")
using .TerraFluxDetection
include("ui_scope.jl")
using .TerraFluxUIScope
include("storm_icons.jl")
include("tracker.jl")
include("map_math.jl")
include("map_layers.jl")
include("hover.jl")
include("intervention_panel.jl")
using .TerraFluxInterventionPanel
include("vortex_panel.jl")
using .TerraFluxVortexPanel
using .TerraFluxMapLayers
using .TerraFluxHover
using .TerraFluxTracker
using .TerraFluxLive
using .TerraFluxLive.TerraFluxSavedSessions
using .TerraFluxGlobe
using .TerraFluxData
using GLMakie
using CUDA
using GeoMakie
using Dates, Printf
export build_viewer, launch

const BG = colorant"#101722"
const PANEL = colorant"#192332"
const INK = colorant"#e8eef5"
const MUTED = colorant"#a6b7c8"
const ACCENT = colorant"#66ded0"

function build_viewer(d::WeatherData; session_root=joinpath(@__DIR__,"..","sessions"),resume_bundle=nothing,
        icon_style_path=joinpath(@__DIR__,"..","assets","storm_tracker","style.toml"),
        weather_style_path=joinpath(@__DIR__,"..","assets","weather","style.toml"))
    weatherstyle=load_weather_style(weather_style_path)
    replacing_data=Ref(false)
    default_truncation=(length(d.lon),length(d.lat))==(96,48) ? 32 : 0
    run_truncation=default_truncation
    if isfile(d.path)
        run_truncation=TerraFluxData.NCDataset(d.path,"r") do ds
            Int(get(ds.attrib,"terraflux_truncation",default_truncation))
        end
    end
    set_theme!(theme_dark(); fontsize=15, backgroundcolor=BG, textcolor=INK,
        Axis=(backgroundcolor=PANEL, xgridcolor=(:white, 0.08), ygridcolor=(:white, 0.08)))
    fig = Figure(size=(1440, 960), figure_padding=26)
    header = GridLayout(fig[1, 1:2])
    Label(header[1, 1], "TERRAFLUX", fontsize=30, font=:bold, color=ACCENT, halign=:left, tellwidth=false)
    Label(header[2, 1], "PHÒNG QUAN SÁT KHÍ QUYỂN", color=MUTED, fontsize=13, halign=:left, tellwidth=false)
    viewmenu = Menu(header[1, 2], options=[("Bản đồ 2D", :map), ("Địa cầu 3D", :globe), ("Storm Tracker", :tracker)], default=1, width=235, halign=:right)
    resetview = Button(header[2, 2], label="Đặt lại góc nhìn", width=235, halign=:right, buttoncolor=PANEL, labelcolor=INK)
    colsize!(header, 1, Relative(0.7))
    physical_widgets = Any[]
    overlay_open=Observable(false)
    intervention_open=Observable(false);intervention_widgets=Any[]
    vortex_open=Observable(false);vortex_widgets=Any[]
    interventionbutton=Button(header[2,1],label="Can thiệp nhiệt",width=190,halign=:center,buttoncolor=PANEL,labelcolor=INK)
    vortexbutton=Button(header[1,1],label="Khởi tạo xoáy",width=190,halign=:center,buttoncolor=PANEL,labelcolor=INK)
    overlaybutton=Button(header[1,1],label="Lớp phủ bản đồ",width=235,halign=:right,buttoncolor=PANEL,labelcolor=INK)
    regionmenu=Menu(header[2,1],options=[("Toàn cầu",:global),("Châu Á–Thái Bình Dương",:asia)],
        default=2,width=235,halign=:right)
    push!(physical_widgets,regionmenu)
    sidebar = GridLayout(fig[2, 1], width=285, tellheight=false)
    push!(physical_widgets, Label(sidebar[1, 1], "01   TRƯỜNG QUAN SÁT", color=MUTED, fontsize=12, halign=:left))
    fieldmenu = Menu(sidebar[2, 1], options=[(field_label(f), f) for f in FIELDS], default=1, width=280)
    push!(physical_widgets, Label(sidebar[3, 1], "02   TẦNG KHÍ QUYỂN", color=MUTED, fontsize=12, halign=:left))
    layermenu = Menu(sidebar[4, 1], options=[(layer_label(d, k), k) for k in eachindex(d.layers)],
        default=length(d.layers), width=280)
    push!(physical_widgets, Label(sidebar[5, 1], "σ gần 1: gần bề mặt\nσ gần 0: tầng cao\nKhông phải độ cao cố định.", color=MUTED, fontsize=13, halign=:left, justification=:left))
    scalemenu=Menu(sidebar[6,1],options=[("Thang khí tượng",:weather),("Theo dữ liệu",:data)],default=1,width=280)
    lockrow = GridLayout(sidebar[7, 1])
    lockscale = Checkbox(lockrow[1, 1], checked=true)
    push!(physical_widgets, Label(lockrow[1, 2], "Khóa thang khi theo dữ liệu", fontsize=12, halign=:left))
    overlays=GridLayout(fig[2,1],width=285,tellheight=false)
    overlay_widgets=Any[]
    function overlay_checkbox(row,label,checked)
        control=Checkbox(overlays[row,1],checked=checked)
        push!(overlay_widgets,control,Label(overlays[row,2],label,fontsize=14,halign=:left))
        control
    end
    push!(overlay_widgets,Label(overlays[1,1:2],"LỚP PHỦ BẢN ĐỒ",fontsize=21,color=ACCENT,font=:bold))
    windtoggle=overlay_checkbox(2,"Hạt gió",true)
    systemstoggle=overlay_checkbox(3,"Hệ thống xoáy / bão",false)
    overlaysource=Menu(overlays[4,1:2],options=[("Ứng viên từ mô hình",:model),("Kịch bản minh họa",:scenario)],default=1,width=280)
    push!(overlay_widgets,overlaysource)
    labelstoggle=overlay_checkbox(5,"Địa danh",true)
    valuestoggle=overlay_checkbox(6,"Giá trị tại địa danh",false)
    nighttoggle=overlay_checkbox(7,"Ngày / đêm (UTC mô phỏng)",false)
    gridtoggle=overlay_checkbox(8,"Lưới tọa độ",true)
    isobartoggle=overlay_checkbox(9,"Đẳng áp khi xem áp suất",true)
    smooth=overlay_checkbox(10,"Mượt bản đồ 2D / 3D",true)
    overlaystatus=Observable("Rê chuột để đọc giá trị ô gần nhất.\nBật hệ thống để thêm vùng xoáy.")
    push!(overlay_widgets,Label(overlays[11,1:2],overlaystatus,fontsize=12,justification=:left,tellwidth=false))
    rowgap!(overlays,12)
    push!(physical_widgets, Label(sidebar[9, 1], "03   ĐIỂM THEO DÕI", color=MUTED, fontsize=12, halign=:left))
    pointtext = Observable("Bấm vào bản đồ để chọn điểm.\nGiá trị tại ô lưới gần nhất.")
    push!(physical_widgets, Label(sidebar[10, 1], pointtext, fontsize=14, halign=:left, justification=:left))
    stattext = Observable("")
    push!(physical_widgets, Label(sidebar[11, 1], stattext, fontsize=12, color=MUTED, halign=:left, justification=:left))
    gridtext = Observable("Lưới đầu ra: $(length(d.lon)) × $(length(d.lat))\n$(length(d.layers)) tầng · $(length(d.times)) thời điểm\nPhóng to không tăng độ phân giải.")
    push!(physical_widgets, Label(sidebar[12, 1], gridtext, fontsize=11, color=MUTED, halign=:left, justification=:left))
    append!(physical_widgets,[fieldmenu,layermenu,scalemenu,lockscale])
    scope_widget_inputs!(vcat(physical_widgets,overlay_widgets,[overlaybutton,interventionbutton,vortexbutton]))
    function set_panels!()
        physical=viewmenu.selection[]!=:tracker
        for widget in physical_widgets;widget.blockscene.visible[]=physical && !overlay_open[] && !intervention_open[] && !vortex_open[];end
        for widget in overlay_widgets;widget.blockscene.visible[]=physical && overlay_open[];end
        for widget in intervention_widgets;widget.blockscene.visible[]=physical && intervention_open[];end
        for widget in vortex_widgets;widget.blockscene.visible[]=physical && vortex_open[];end
        vortexbutton.blockscene.visible[]=physical
        vortexbutton.label[]=vortex_open[] ? "Đóng tạo xoáy" : "Khởi tạo xoáy"
        regionmenu.blockscene.visible[]=viewmenu.selection[]==:map
        overlaybutton.blockscene.visible[]=physical
        interventionbutton.blockscene.visible[]=physical
        interventionbutton.label[]=intervention_open[] ? "Đóng can thiệp" : "Can thiệp nhiệt"
        overlaybutton.label[]=overlay_open[] ? "Trường quan sát" : "Lớp phủ bản đồ"
    end
    on(overlaybutton.clicks) do _;overlay_open[]=!overlay_open[];intervention_open[]=false;vortex_open[]=false;set_panels!();end
    on(interventionbutton.clicks) do _;intervention_open[]=!intervention_open[];overlay_open[]=false;vortex_open[]=false;set_panels!();end
    on(vortexbutton.clicks) do _;vortex_open[]=!vortex_open[];intervention_open[]=false;overlay_open[]=false;set_panels!();end
    rowgap!(sidebar, 6)
    rowsize!(sidebar,8,Fixed(0))
    maparea = GridLayout(fig[2, 2])
    title = Observable("")
    Label(maparea[1, 1:2], title, font=:bold, fontsize=16)
    ax = Axis(maparea[2, 1], xlabel="Kinh độ", ylabel="Vĩ độ", aspect=DataAspect(),
        xticks=(-180:15:180), yticks=(-90:15:90),xgridcolor=(:black,0.35),ygridcolor=(:black,0.35),
        xgridstyle=:dot,ygridstyle=:dot,xgridvisible=gridtoggle.checked,ygridvisible=gridtoggle.checked)
    function reset_map!()
        regionmenu.selection[]==:asia ? limits!(ax,60,180,-5,55) : limits!(ax,-180,180,-90,90)
    end
    on(regionmenu.selection) do _;reset_map!();end
    reset_map!()
    field = Observable(:temp)
    layer = Observable(length(d.layers))
    time = Observable(1)
    selected = Observable{Union{Nothing,Tuple{Int,Int}}}(nothing)
    limits = Observable(weather_limits(weatherstyle,d,:temp,layer[],1))
    mapvalues = Observable(vcat(frame(d, :temp, layer[], 1), frame(d, :temp, layer[], 1)[1:1, :]))
    cmap = Observable(weather_palette(weatherstyle,:temp))
    heat = heatmap!(ax, vcat(d.lon, d.lon[1]+360), d.lat, mapvalues;
        colorrange=limits, colormap=cmap, nan_color=:transparent, interpolate=smooth.checked)
    lines!(ax, GeoMakie.coastlines(); color=(:black,0.8), linewidth=0.7, xautolimits=false, yautolimits=false,depth_shift=-0.01f0)
    pressure_values=Observable(fill(NaN32,length(d.lon)+1,length(d.lat)))
    contour_visible=Observable(false)
    isobars=contour!(ax,vcat(d.lon,d.lon[1]+360),d.lat,pressure_values;
        levels=collect(880.:weatherstyle["pressure"]["isobar_interval_hpa"]:1080.),
        color=(:white,0.8),linewidth=0.8,labels=true,labelsize=10,visible=contour_visible)
    marker = Observable(Point2f[])
    scatter!(ax, marker; markersize=14, color=ACCENT, strokecolor=:black, strokewidth=2)
    unittext = Observable("°C")
    colorbar = Colorbar(maparea[2, 2], heat, label=unittext, width=16)
    helptext = Observable("Bản đồ 2D • Cuộn: thu phóng • Chuột phải: di chuyển • Bấm trái: đọc giá trị")
    helpcaption=lift(helptext,systemstoggle.checked,overlaysource.selection,viewmenu.selection) do text,enabled,source,mode
        !enabled || mode==:tracker ? text : text*"\n"*(source==:scenario ?
            "HỆ THỐNG: KỊCH BẢN MINH HỌA · Không phải nhận diện từ mô hình" :
            "HỆ THỐNG: ỨNG VIÊN MÔ HÌNH W/C/L? · Không gán cấp bão SSHWS")
    end
    Label(maparea[3, 1:2], helpcaption, fontsize=11, color=MUTED)
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
    vertexcolors = Observable(globe_colors(display_frame(d,:temp,layer[],time[])))
    cellmesh=mesh!(globe, Point3f.(points), [Makie.GeometryBasics.TriangleFace(f...) for f in faces];
        color=vertexcolors, colormap=cmap, colorrange=limits, shading=NoShading,
        nan_color=:transparent,visible=lift(!,smooth.checked))
    smoothgeometry=smooth_globe_geometry(d.lon,d.lat;factor=length(d.lon)<=128 ? 3 : 2)
    smoothcolors=Observable(smooth_globe_colors(frame(d,:temp,layer[],time[]),smoothgeometry))
    smoothmesh=mesh!(globe,Point3f.(smoothgeometry.points),[Makie.GeometryBasics.TriangleFace(f...) for f in smoothgeometry.faces];
        color=smoothcolors,colormap=cmap,colorrange=limits,shading=NoShading,nan_color=:transparent,visible=smooth.checked)
    coastpoints = Makie.convert_arguments(Lines, GeoMakie.coastlines())[1]
    lines!(globe, Point3f.(smooth_sphere_lines(coastpoints));
        color=(:white,0.7), linewidth=0.8)
    graticule = Point3f[]
    for lat in -60:30:60
        append!(graticule, [Point3f(sphere_point(lon,lat;radius=1.006)) for lon in -180:0.5:180])
        push!(graticule, Point3f(NaN))
    end
    for lon in -180:30:150
        append!(graticule, [Point3f(sphere_point(lon,lat;radius=1.006)) for lat in -90:0.5:90])
        push!(graticule, Point3f(NaN))
    end
    lines!(globe, graticule; color=(:white,0.15), linewidth=0.6,visible=gridtoggle.checked)
    globe_marker = Observable(Point3f[])
    scatter!(globe, globe_marker; color=ACCENT, markersize=14, strokecolor=:black, strokewidth=2)
    reset_globe() = update_cam!(globe.scene, Vec3f(sphere_point(105,20;radius=3.5)), Vec3f(0), Vec3f(0,0,1))
    reset_globe()
    on(resetview.clicks) do _
        reset_map!()
        reset_globe()
        tracker.reset!()
    end
    particleconfig=weatherstyle["particles"]
    particles=WindParticles(count=particleconfig["count"],trail_steps=particleconfig["trail_steps"],
        lifetime=particleconfig["lifetime_seconds"],speed=particleconfig["visual_seconds_per_second"])
    wind2d=Observable(Point2f.(particle_segments(particles)))
    wind3d=Observable(fill(Point3f(NaN),length(wind2d[])))
    windcolors=repeat([RGBAf(1,1,1,0.8f0*(1-(h-1)/(particleconfig["trail_steps"]-1)))
        for h in 1:particleconfig["trail_steps"]-1 for _ in 1:2],particleconfig["count"])
    linesegments!(ax,wind2d;color=windcolors,linewidth=1.1,
        visible=lift((show,mode)->show && mode==:map,windtoggle.checked,viewmenu.selection),depth_shift=-0.005f0)
    linesegments!(globe,wind3d;color=windcolors,linewidth=1.1,
        visible=lift((show,mode)->show && mode==:globe,windtoggle.checked,viewmenu.selection))
    wind_context=Ref{Any}((d,layer[],time[]))
    function update_wind_frame!()
        previous=wind_context[]
        if previous[1] !== d || previous[2]!=layer[] || previous[3]!=time[]
            clear_trails!(particles)
            wind2d[]=fill(Point2f(NaN),length(wind2d[]))
            wind3d[]=fill(Point3f(NaN),length(wind3d[]))
            wind_context[]=(d,layer[],time[])
        end
    end
    function animate_wind!(dt)
        mode=viewmenu.selection[]
        windtoggle.checked[] && mode in (:map,:globe) || return
        if mode==:map
            rectangle=ax.finallimits[]
            bounds=(max(-180.,rectangle.origin[1]),min(180.,rectangle.origin[1]+rectangle.widths[1]),
                max(-80.,d.lat[1],rectangle.origin[2]),min(80.,d.lat[end],rectangle.origin[2]+rectangle.widths[2]))
        else
            bounds=(-180.,180.,max(-80.,d.lat[1]),min(80.,d.lat[end]))
        end
        bounds[1]<bounds[2] && bounds[3]<bounds[4] || return
        any(abs.(collect(bounds).-collect(particles.bounds)).>0.05) && reset_particles!(particles,bounds)
        step_particles!(particles,d,layer[],time[],dt)
        points=particle_segments(particles)
        if mode==:map
            wind2d[]=Point2f.(points)
        else
            wind3d[]=[all(isfinite,p) ? Point3f(sphere_point(p...;radius=1.008)) : Point3f(NaN) for p in points]
        end
    end
    livepanel = GridLayout(fig[3, 1:2])
    livestatus = Observable("Chọn chất lượng bên dưới, rồi bấm Phiên mới · mỗi bước 6 giờ")
    Label(livepanel[1,1:8],livestatus;fontsize=12,color=ACCENT,halign=:left,tellwidth=false)
    sourcemenu = Menu(livepanel[2,1],options=[("Tệp đã mở",:file),("Phiên mô phỏng",:live)],default=1,width=170)
    durationmenu=Menu(livepanel[2,2],options=[("10 ngày",10),("30 ngày",30),("60 ngày",60)],default=3,width=110)
    newrun = Button(livepanel[2,3],label="Phiên mới",buttoncolor=PANEL,labelcolor=INK)
    runmodel = Button(livepanel[2,4],label="Chạy",buttoncolor=PANEL,labelcolor=INK)
    pausemodel = Button(livepanel[2,5],label="Tạm dừng",buttoncolor=PANEL,labelcolor=INK)
    stepmodel = Button(livepanel[2,6],label="+6 giờ",buttoncolor=PANEL,labelcolor=INK)
    stopmodel = Button(livepanel[2,7],label="Kết thúc",buttoncolor=PANEL,labelcolor=INK)
    Label(livepanel[2,8],"Độc lập với phát lại",fontsize=12,color=MUTED)
    quality=GridLayout(livepanel[3,1:8])
    Label(quality[1,1],"Chất lượng phiên mới",fontsize=12,color=MUTED)
    quality_T=run_truncation in (21,32,63,85) ? run_truncation : 32
    quality_layers=length(d.layers) in (8,16,24,32) ? length(d.layers) : 8
    resolutionmenu=Menu(quality[1,2],options=[("T$n",n) for n in (21,32,63,85)],
        default=findfirst(==(quality_T),(21,32,63,85)),width=110)
    levelsmenu=Menu(quality[1,3],options=[("$n tầng",n) for n in (8,16,24,32)],
        default=findfirst(==(quality_layers),(8,16,24,32)),width=110)
    has_cuda=try;CUDA.functional();catch;false;end
    backendmenu=Menu(quality[1,4],options=has_cuda ? [("CPU","cpu"),("NVIDIA CUDA","cuda")] : [("CPU","cpu")],default=1,width=155)
    Label(quality[1,5],"Áp dụng khi bấm Phiên mới · T cao hơn tốn thêm bộ nhớ/phép tính",fontsize=11,color=MUTED,tellwidth=false)
    active_quality=Ref{Any}(nothing)
    persistence=GridLayout(livepanel[4,1:8])
    savesession=Button(persistence[1,1],label="Lưu phiên",buttoncolor=PANEL,labelcolor=INK)
    savedpath=Textbox(persistence[1,2],stored_string="",placeholder="Dán đường dẫn session.toml hoặc thư mục bản lưu",reset_on_defocus=false,tellwidth=false)
    opensession=Button(persistence[1,3],label="Mở phiên đã lưu",buttoncolor=PANEL,labelcolor=INK)
    colsize!(persistence,1,Fixed(130));colsize!(persistence,3,Fixed(160))
    persistence_notice=Observable("Lưu khi tạm dừng · Mở bằng đường dẫn session.toml hoặc thư mục bản lưu.")
    Label(persistence[2,1:2],persistence_notice,fontsize=11,color=MUTED,tellwidth=false,word_wrap=true)
    abexperiments=Button(persistence[2,3],label="Thí nghiệm A/B",buttoncolor=PANEL,labelcolor=INK)
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
            !as_globe && (regionmenu.i_selected[]=1)
            viewmenu.i_selected[] = as_globe ? 2 : 1
            if as_globe
                update_cam!(globe.scene,Vec3f(sphere_point(location...;radius=3.5)),Vec3f(0),Vec3f(0,0,1))
            end
        end,
        on_start=timestamp -> set_close_to!(slider,argmin(abs.(d.times .- timestamp))))
    intervention=build_intervention_panel(fig[2,1],ax,globe,viewmenu.selection,intervention_open,selected,layer;
        get_data=()->d,on_apply=spec->request_thermal("thermal";patch=spec),on_undo=()->request_thermal("undo_thermal"),
        on_layer=k->(layermenu.i_selected[]=k))
    append!(intervention_widgets,intervention.widgets);scope_widget_inputs!(intervention_widgets)
    vortex=build_vortex_panel(fig[2,1],ax,globe,viewmenu.selection,vortex_open,selected;
        get_data=()->d,on_apply=spec->request_thermal("vortex";patch=spec),on_undo=()->request_thermal("undo_edit"))
    append!(vortex_widgets,vortex.widgets);scope_widget_inputs!(vortex_widgets)
    layers=build_map_layers(ax,globe,smoothgeometry,viewmenu.selection;systems=systemstoggle.checked,
        labels=labelstoggle.checked,values=valuestoggle.checked,night=nighttoggle.checked,style=tracker.style)
    last_layer_result=Ref{Any}(nothing)
    function refresh_layers!()
        set=nothing
        if systemstoggle.checked[]
            result=overlaysource.selection[]==:scenario ? tracker.scenario : model_provider()
            last_layer_result[]=result
            if result isa TerraFluxStorms.StormScenario
                set=result;overlaystatus[]="KỊCH BẢN MINH HỌA\nKhông phải nhận diện từ mô hình."
            elseif result isa ModelStormSet
                set=result;overlaystatus[]="Ứng viên mô hình W/C/L?\nVùng gió xoáy sơ bộ, không SSHWS."
            else
                overlaystatus[]=result isa AbstractString ? first(result,180) : "Đang phân tích áp suất/gió/nhiệt…"
            end
        else
            overlaystatus[]="Rê chuột để đọc trường đang chọn.\nBật hệ thống để thêm vùng xoáy."
        end
        layers.update!(d,mapvalues[],field[],layer[],d.times[time[]],set)
        layers.omitted[]>0 && (overlaystatus[]*="\nẨn $(layers.omitted[]) tâm: giới hạn 256 icon.")
    end
    menus=(viewmenu,fieldmenu,layermenu,scalemenu,regionmenu,sourcemenu,durationmenu,resolutionmenu,levelsmenu,backendmenu,overlaysource,
        tracker.source_menu,tracker.systemmenu,tracker.unitmenu,tracker.filter_menu,tracker.region,intervention.menu)
    hover=build_hover(fig,ax,globe,tracker,viewmenu.selection,menus,layers,systemstoggle.checked;
        get_data=()->d,get_field=()->field[],get_layer=()->layer[],get_time=()->d.times[time[]],get_values=()->mapvalues[])
    function poll_layers!()
        systemstoggle.checked[] && overlaysource.selection[]==:model || return
        result=model_provider()
        if result!==last_layer_result[]
            refresh_layers!();hover.update!()
        end
    end
    on(viewmenu.selection) do mode
        is_globe = mode == :globe
        is_tracker = mode == :tracker
        ax.blockscene.visible[] = mode == :map
        ax.scene.visible[] = mode == :map
        globe.blockscene.visible[] = is_globe
        globe.scene.visible[] = is_globe
        colorbar.blockscene.visible[] = !is_tracker
        overlay_open[]=false;intervention_open[]=false;vortex_open[]=false;set_panels!();hover.visible[]=false
        tracker.set_active!(is_tracker)
        helptext[] = is_tracker ? "Chọn nguồn trong Storm Tracker • Biểu tượng là vị trí đại diện, không chỉ bán kính gió" :
            is_globe ? "Địa cầu 3D • Kéo chuột trái: xoay • Cuộn: thu phóng • Bấm trái: đọc giá trị" :
            "Bản đồ 2D • Cuộn: thu phóng • Chuột phải: di chuyển • Bấm trái: đọc giá trị"
        refresh()
    end
    limitcache=Dict{Tuple{Symbol,Int,Bool},Tuple{Float32,Float32}}()
    palettecache=Dict{Symbol,Vector{RGBAf}}()
    function refresh_point()
        cell = selected[]
        if cell !== nothing
            i, j = cell
            value = mapvalues[][i,j]
            val = isfinite(value) ? @sprintf("%.3f", value) : "Thiếu dữ liệu"
            pointtext[] = @sprintf("Ô lưới: %.2f° / %.2f°\n%s %s", d.lon[i], d.lat[j], val, display_unit(field[]))
        end
    end
    function refresh(; rescale=true)
        replacing_data[] && return
        f, k, t = field[], layer[], time[]
        a = display_frame(d,f,k,t)
        mapvalues[] = vcat(a, a[1:1, :])
        vertexcolors[] = globe_colors(a)
        smoothcolors[]=smooth_globe_colors(a,smoothgeometry)
        palette=get!(()->weather_palette(weatherstyle,f),palettecache,f)
        cmap[]===palette || (cmap[]=palette)
        unittext[] = display_unit(f)
        if rescale || !lockscale.checked[]
            standard=scalemenu.selection[]==:weather
            limits[]=if lockscale.checked[]
                get!(limitcache,(f,k,standard)) do
                    weather_limits(weatherstyle,d,f,k,t;standard,locked=true)
                end
            else
                weather_limits(weatherstyle,d,f,k,t;standard,locked=false)
            end
        end
        description = field_context(d,f,k)
        title[] = "$(field_label(f)) / $(display_unit(f))\n$description"
        clocktext[] = "$(Dates.format(d.times[t], dateformat"yyyy-mm-dd HH:MM"))   ·   Khung $t / $(length(d.times))"
        bounds=finite_extrema(a)
        stattext[] = bounds===nothing ? (f in (:sst,:lst) && !haskey(d.fields,f) ? "Tệp chưa có nhiệt độ bề mặt hoặc mặt nạ đất/biển.\nCần tạo mô phỏng mới để ghi trường này." : f==:rh && !haskey(d.fields,:pres) ? "Cần áp suất bề mặt để tính RH.\nTệp cũ chỉ có độ ẩm riêng." : f==:rh && t==1 ? "RH thiếu dữ liệu khởi tạo.\nThử khung tiếp theo (+6 giờ)." : f == :mslp && t == 1 ? "Áp suất mốc khởi tạo\nchưa được mô hình tính." : "Khung này thiếu dữ liệu.") : @sprintf("Toàn bản đồ / %s\nMin  %.3f\nMax  %.3f", display_unit(f), bounds[1], bounds[2])
        contour_visible[]=viewmenu.selection[]==:map && f==:mslp && isobartoggle.checked[]
        contour_visible[] && (pressure_values[]=vcat(a,a[1:1,:]))
        ticks=get(Dict(:temp=>(-30:10:50),:sst=>(-30:10:50),:lst=>(-30:10:50),:wind=>(0:20:120),:rh=>(0:25:100),:mslp=>(970:15:1045)),f,Makie.automatic)
        colorbar.ticks[]=scalemenu.selection[]==:weather ? ticks : Makie.automatic
        update_wind_frame!()
        refresh_point()
        tracker.clock[] = d.times[t]
        if viewmenu.selection[] == :tracker
            title[] = tracker.title[]
        end
        refresh_layers!();hover.update!()
    end
    on(tracker.title) do text
        viewmenu.selection[] == :tracker && (title[]=text)
    end
    on(fieldmenu.selection) do f
        field[] = f
        refresh()
    end
    on(layermenu.selection) do k
        k===nothing && return
        layer[] = k
        refresh()
    end
    on(lockscale.checked) do _
        refresh()
    end
    on(scalemenu.selection) do _;refresh();end
    on(isobartoggle.checked) do _;refresh();end
    for toggle in (systemstoggle.checked,overlaysource.selection,labelstoggle.checked,valuestoggle.checked,nighttoggle.checked)
        on(_->refresh(),toggle)
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
        if viewmenu.selection[]==:map && event.button == Mouse.left && event.action == Mouse.press && is_mouseinside(ax.scene) &&
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
    last_intervention_notice=Ref("")
    last_saved_seen=Ref("")
    persistence_operation=Ref("")
    save_previous_path=Ref("")
    function replace_data!(next)
        grid_changed=next.lon!=d.lon || next.lat!=d.lat
        levels_changed=next.layers!=d.layers
        location=selected[]===nothing ? nothing : (d.lon[selected[][1]],d.lat[selected[][2]])
        k=levels_changed ? argmin(abs.(next.layers .- d.layers[layer[]])) : layer[]
        if grid_changed || levels_changed
            selected[]=nothing
        end
        empty!(limitcache)
        replacing_data[]=true
        try
            d=next
            playing[]=false
            if grid_changed
                points,faces=globe_geometry(d.lon,d.lat)
                smoothgeometry=smooth_globe_geometry(d.lon,d.lat;factor=length(d.lon)<=128 ? 3 : 2)
                a=display_frame(d,field[],k,length(d.times))
                mapvalues.val=vcat(a,a[1:1,:])
                pressure_values.val=fill(NaN32,size(mapvalues[]))
                vertexcolors.val=globe_colors(a)
                smoothcolors.val=smooth_globe_colors(a,smoothgeometry)
                # Submit geometry and its payload together: changing one input at a
                # time can render a new matrix against the previous grid/mesh.
                Makie.update!(heat;arg1=vcat(d.lon,d.lon[1]+360),arg2=d.lat,arg3=mapvalues[])
                Makie.update!(isobars;arg1=vcat(d.lon,d.lon[1]+360),arg2=d.lat,arg3=pressure_values[])
                Makie.update!(cellmesh;arg1=Point3f.(points),arg2=[Makie.GeometryBasics.TriangleFace(f...) for f in faces],color=vertexcolors[])
                Makie.update!(smoothmesh;arg1=Point3f.(smoothgeometry.points),arg2=[Makie.GeometryBasics.TriangleFace(f...) for f in smoothgeometry.faces],color=smoothcolors[])
            end
            if levels_changed
                options=[(layer_label(d,i),i) for i in eachindex(d.layers)]
                layermenu.options[]=options
                intervention.menu.options[]=options
                layer[]=k
                layermenu.i_selected[]=k
                intervention.menu.i_selected[]=k
            end
            time[]=length(d.times)
            slider.range[]=1:length(d.times)
            set_close_to!(slider,length(d.times))
            gridtext[]="Lưới đầu ra: $(length(d.lon)) × $(length(d.lat))\n$(length(d.layers)) tầng · $(length(d.times)) thời điểm\nPhóng to không tăng độ phân giải."
            sourceinfo[]=sourcemenu.selection[]==:live && history[]!==nothing && d===history[] ? "PHÁT LẠI / phiên live · 2 khung/giây · $(basename(session[].directory))" :
                "PHÁT LẠI / tệp đã mở · 2 khung/giây · $(basename(original.path))"
        finally
            replacing_data[]=false
        end
        if (grid_changed || levels_changed) && location!==nothing
            selected[]=nearest_cell(d,location...)
        end
        refresh()
        intervention.refresh!();vortex.refresh!()
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
        if imported[]==0 && history[]===nothing && length(status["files"])>1
            history[]=load_live_history(status["files"])
            imported[]=length(status["files"])
        end
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
            "complete"=>"Đã hoàn tất", "stopped"=>"Đã kết thúc", "error"=>"Lỗi mô phỏng","saving"=>"Đang lưu phiên")
        message = get(text,state,state)
        pending = get(status,"sequence",0) < session[].sequence
        pending && (message *= " · lệnh đang chờ xử lý")
        get(status,"pending_edit",false) && (message*=" · có tác động chờ mốc mới")
        state == "error" && (message *= " · " * first(get(status,"error","Xem worker.log"),180))
        command_error=get(status,"command_error","")
        isempty(command_error) || (message*=" · từ chối: "*first(command_error,100))
        saved=get(status,"last_saved","")
        if !isempty(saved) && saved!=last_saved_seen[]
            Makie.set!(savedpath,saved);last_saved_seen[]=saved
            message*=" · Đã lưu phiên (đường dẫn ở ô bên dưới)"
        end
        if persistence_operation[]=="save" && !isempty(saved) && saved!=save_previous_path[]
            persistence_notice[]="Đã lưu đầy đủ. Có thể kết thúc phiên rồi mở lại bằng đường dẫn ở trên."
            persistence_operation[]=""
        elseif persistence_operation[]=="save" && (state=="error" || (!pending && state!="saving"))
            problem=isempty(command_error) ? get(status,"error","") : command_error
            isempty(problem) && (problem="Yêu cầu đã dừng hoặc chưa hoàn tất.")
            persistence_notice[]="Không lưu được: "*first(problem,220)
            persistence_operation[]=""
        elseif persistence_operation[]=="open" && state in ("paused","complete","error")
            at_limit=status["completed"]>=get(status,"max_chunks",typemax(Int))
            persistence_notice[]=state=="error" ? "Không khôi phục được: "*first(status["error"],220) : state=="complete" || at_limit ? "Đã mở mốc cuối. Phiên đã đủ giới hạn thời lượng." : "Đã khôi phục tại $(status["model_time"]). Bấm Chạy hoặc +6 giờ để tính tiếp."
            persistence_operation[]=""
        end
        budget=haskey(status,"max_chunks") ? " / $(status["max_chunks"]*6)" : ""
        quality_text=active_quality[]===nothing ? "" : " · T$(active_quality[].truncation) / $(active_quality[].layers) tầng / $(uppercase(active_quality[].backend))"
        live_message="$message$quality_text · Đã tính $(status["completed"]*6)$budget giờ · $(basename(session[].directory))"
        livestatus[]==live_message || (livestatus[]=live_message)
        notice=!isempty(command_error) ? first(command_error,240) : pending ? "Đang xử lý lệnh…" :
            get(status,"pending_edit",false) ? "Đã áp dụng. Khung đã lưu vẫn là trước tác động; bấm +6 giờ để xem phản ứng.\n"*get(status,"edit_summary","") :
            isempty(get(status,"edit_summary","")) ? "Chọn cấu hình và xem trước.\nChỉ dùng ở mốc cuối của phiên live đã tạm dừng." : get(status,"edit_summary","")
        if notice!=last_intervention_notice[]
            intervention.message[]=notice;vortex.message[]=notice;last_intervention_notice[]=notice
        end
        status
    end
    function request_thermal(action;patch=nothing)
        session[]===nothing && error("Tạo phiên live và tính +6 giờ trước.")
        history[]!==nothing && sourcemenu.selection[]==:live && d===history[] && time[]==length(d.times) ||
            error("Mở nguồn Phiên mô phỏng và chọn mốc cuối đã lưu.")
        status=read_status(session[])
        get(status,"model_time","")==string(d.times[end]) || error("Mốc đang xem chưa khớp trạng thái mô hình.")
        send_command!(session[],action;patch)
        poll_live!()
    end
    on(newrun.clicks) do _
        try
            if session[] !== nothing && process_running(session[].process)
                livestatus[] = "Phiên hiện tại còn hoạt động. Bấm Kết thúc trước khi tạo phiên mới."
            else
                config=(truncation=resolutionmenu.selection[],layers=levelsmenu.selection[],backend=backendmenu.selection[])
                session[] = start_session(;root=session_root,max_chunks=4durationmenu.selection[],config...)
                active_quality[]=config
                history[] = nothing
                imported[] = 0
                replace_data!(original)
                last_saved_seen[]="";persistence_operation[]=""
                persistence_notice[]=config.backend=="cuda" ? "Phiên CUDA · Lưu/khôi phục trạng thái chưa hỗ trợ; có thể xem lại NetCDF." : "Phiên mới · Tạm dừng sau ít nhất +6 giờ để lưu."
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
    on(savesession.clicks) do _
        try
            session[]===nothing && error("Tạo phiên live trước khi lưu.")
            save_previous_path[]=get(read_status(session[]),"last_saved","")
            send_command!(session[],"save")
            persistence_operation[]="save";persistence_notice[]="Đang lưu trạng thái và lịch sử. Chờ thông báo hoàn tất trước khi đóng."
            poll_live!()
        catch err
            persistence_notice[]=first(sprint(showerror,err),240)
        end
    end
    function open_saved!(path)
        if session[]!==nothing && process_running(session[].process)
            error("Bấm Kết thúc và chờ phiên hiện tại kết thúc trước khi mở bản lưu.")
        end
        path=strip(path)
        length(path)>=2 && startswith(path,'"') && endswith(path,'"') && (path=path[nextind(path,firstindex(path)):prevind(path,lastindex(path))])
        meta=saved_manifest(path;verify=false)
        session[]=resume_session(path;root=session_root)
        active_quality[]=(truncation=meta["config"]["truncation"],layers=meta["config"]["layers"],backend="cpu")
        history[]=nothing;imported[]=0;last_saved_seen[]=""
        persistence_operation[]="open";persistence_notice[]="Đang kiểm tra và khôi phục phiên đã lưu…"
        sourcemenu.i_selected[]=2
        poll_live!()
    end
    on(opensession.clicks) do _
        try;open_saved!(savedpath.displayed_string[]);catch err;persistence_notice[]=first(sprint(showerror,err),260);end
    end
    on(abexperiments.clicks) do _
        try
            project=abspath(joinpath(@__DIR__,".."))
            command=`$(Base.julia_cmd()) --threads=2 --project=$project $(joinpath(project,"compare_experiments.jl"))`
            path=strip(savedpath.displayed_string[])
            run(isempty(path) ? command : `$command $path`;wait=false)
        catch err
            persistence_notice[]=first(sprint(showerror,err),240)
        end
    end
    refresh()
    notify(viewmenu.selection)
    if resume_bundle!==nothing
        try
            open_saved!(resume_bundle)
        catch
            try;session[]===nothing || stop_session!(session[]);catch;end
            rethrow()
        end
    end
    (; fig, ax, globe, tracker, session, history, sourcemenu, newrun, runmodel, pausemodel, stepmodel, stopmodel,
        livestatus, poll_live!, replace_data!, savesession,savedpath,opensession,abexperiments,persistence_notice,open_saved!, viewmenu, resetview, vertexcolors, globe_marker, fieldmenu, layermenu, lockscale, slider, selected, field, layer, time,
        pointtext, mapvalues, limits, play, back, forward, playing,
        weatherstyle,scalemenu,regionmenu,windtoggle,isobartoggle,smooth,isobars,contour_visible,durationmenu,resolutionmenu,levelsmenu,backendmenu,active_quality,
        overlaybutton,overlay_open,overlaysource,systemstoggle,labelstoggle,valuestoggle,nighttoggle,gridtoggle,
        layers,poll_layers!,hover,smoothcolors,smoothgeometry,helpcaption,intervention,intervention_open,interventionbutton,
        particles,wind2d,wind3d,animate_wind!,heat,cmap,colorbar,stattext,vortex,vortexbutton,vortex_open)
end

function advance_playback!(viewer)
    viewer.playing[] || return
    if viewer.time[] < length(viewer.slider.range[])
        set_close_to!(viewer.slider, viewer.time[] + 1)
    else
        viewer.playing[] = false
    end
end

function saved_weather(path)
    meta=saved_manifest(path)
    root=dirname(saved_manifest_path(path))
    load_live_history([payload_path(root,name) for name in meta["history"]])
end
function launch(path)
    GLMakie.activate!()
    saved=isdir(path) || endswith(lowercase(path),".toml")
    data = saved ? saved_weather(path) : load_weather(path)
    viewer = build_viewer(data;resume_bundle=saved ? path : nothing)
    screen = try
        display(viewer.fig)
    catch
        try;viewer.session[]===nothing || stop_session!(viewer.session[]);catch;end
        rethrow()
    end
    # Data polling/playback keep their original cadence regardless of icon style FPS.
    ticker = @async begin
        tick=0
        while isopen(screen)
            sleep(0.25)
            isopen(screen) || break
            try
                viewer.poll_live!()
                viewer.tracker.poll_model!()
                viewer.poll_layers!()
            catch err
                viewer.livestatus[] = "Không đọc được phiên: " * first(sprint(showerror,err),180)
            end
            tick+=1
            iseven(tick) && advance_playback!(viewer)
        end
    end
    animator = @async begin
        started=time_ns()
        previous=0.0
        while isopen(screen)
            sleep(1/viewer.tracker.style.refresh_fps)
            isopen(screen) || break
            seconds=Float64(time_ns()-started)/1e9
            viewer.tracker.animate!(seconds)
            viewer.animate_wind!(seconds-previous)
            previous=seconds
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
