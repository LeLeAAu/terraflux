module TerraFluxTracker
using ..TerraFluxStorms
using GLMakie, GeoMakie, Dates, Printf
export build_tracker

function build_tracker(sideposition, mapposition, timestamp; on_physical, on_start,
        scenario_path=joinpath(@__DIR__,"..","scenarios","demo_storms.toml"))
    scenario = load_scenario(scenario_path)
    active = Observable(false)
    clock = Observable(timestamp)
    panel = GridLayout(sideposition;width=285,tellheight=false)
    widgets = Any[]
    add(widget) = (push!(widgets,widget);widget)
    add(Label(panel[1,1],"STORM TRACKER",fontsize=22,font=:bold,color="#66ded0",halign=:left))
    add(Label(panel[2,1],"KỊCH BẢN MINH HỌA\nKhông phải nhận diện từ mô hình.",fontsize=12,color="#f8c448",halign=:left,justification=:left))
    systemmenu = add(Menu(panel[3,1],options=[(s.id*" / "*s.name,s.id) for s in scenario.systems],default=1,width=280))
    unitmenu = add(Menu(panel[4,1],options=[("Gió: knot",:kn),("Gió: m/s",:ms),("Gió: km/h",:kmh),("Gió: mph",:mph)],default=1,width=280))
    card = Observable("")
    add(Label(panel[5,1],card,fontsize=14,halign=:left,justification=:left,tellwidth=false))
    buttons = GridLayout(panel[6,1])
    physical = add(Button(buttons[1,1],label="Trường vật lý",buttoncolor="#192332",labelcolor=:white))
    globe = add(Button(buttons[1,2],label="Địa cầu 3D",buttoncolor="#192332",labelcolor=:white))
    options = GridLayout(panel[7,1])
    trails = add(Checkbox(options[1,1],checked=true))
    add(Label(options[1,2],"Giữ lịch sử quỹ đạo",halign=:left,fontsize=13))
    reduced = add(Checkbox(options[2,1],checked=false))
    add(Label(options[2,2],"Giảm hiệu ứng / ngừng xoay",halign=:left,fontsize=13))
    region = add(Menu(panel[8,1],options=[("Tây Bắc Thái Bình Dương",:wpac),("Toàn cầu",:global)],default=1,width=280))
    start = add(Button(panel[9,1],label="Tới đầu kịch bản",buttoncolor="#192332",labelcolor=:white))
    add(Label(panel[10,1],"Gió kịch bản: duy trì 1 phút / 10 m.\nChưa có ACE, ENSO và tác động.\nBiểu tượng không phải bán kính bão.",fontsize=11,color="#a6b7c8",halign=:left,justification=:left))
    rowgap!(panel,12)
    ax = Axis(mapposition;backgroundcolor="#070e20",xlabel="Kinh độ",ylabel="Vĩ độ",aspect=DataAspect(),
        xticks=100:10:180,yticks=-90:10:90,xgridcolor=(:white,0.15),ygridcolor=(:white,0.15))
    poly!(ax,GeoMakie.land();color="#192f2b",strokewidth=0)
    lines!(ax,GeoMakie.coastlines();color="#91aaa6",linewidth=0.7)
    cities = [("Hong Kong",114.16,22.30),("Manila",120.98,14.60),("Davao",125.61,7.07),
        ("Guam",144.79,13.44),("Palau",134.50,7.50)]
    scatter!(ax,[Point2f(c[2],c[3]) for c in cities];color="#90aba3",markersize=3)
    text!(ax,[Point2f(c[2],c[3]) for c in cities];text=[c[1] for c in cities],offset=(4,-8),fontsize=10,color="#c3cec9")
    function reset!()
        ax.xticks[] = region.selection[] == :global ? (-180:60:180) : (100:10:180)
        ax.yticks[] = region.selection[] == :global ? (-90:30:90) : (0:10:40)
        region.selection[] == :global ? limits!(ax,-180,180,-90,90) : limits!(ax,100,180,0,35)
    end
    on(region.selection) do _; reset!(); end
    reset!()
    # Fixed screen-size spiral silhouette: the icon is not a physical wind-radius footprint.
    shape = Point2f[]
    for angle in range(0,2pi;length=181)[1:end-1]
        radius = 0.62+0.38cos(3angle)
        theta = angle+1.6(1-radius)
        push!(shape,Point2f(0.5radius*cos(theta),0.5radius*sin(theta)))
    end
    spiral = Makie.GeometryBasics.Polygon(shape)
    handles = Dict{String,Any}()
    categories = (:L,:D,:S,:C1,:C2,:C3,:C4,:C5,:SD,:SS,:EX,:RL)
    for system in scenario.systems
        position = Observable([Point2f(0,0)])
        visible = Observable(false)
        color = Observable(parse(RGBAf,CATEGORY_STYLES[:L][3]))
        rotation = Observable(0f0)
        symbol = Observable("L")
        name = Observable(system.id)
        size = Observable(64f0)
        glowcolor = lift(c -> RGBAf(c.r,c.g,c.b,0.16),color)
        scatter!(ax,position;color=glowcolor,markersize=74,visible)
        scatter!(ax,position;marker=spiral,color,markersize=size,rotation=rotation,visible)
        scatter!(ax,position;color,markersize=31,strokecolor="#dcecf5",strokewidth=1.3,visible)
        text!(ax,position;text=symbol,align=(:center,:center),fontsize=18,font=:bold,color="#091320",visible)
        text!(ax,position;text=name,offset=(34,8),fontsize=15,font=:bold,color=:white,
            strokecolor=(:black,0.8),strokewidth=1.2,visible)
        paths = Dict{Symbol,Observable{Vector{Point2f}}}()
        for category in categories
            points = Observable(Point2f[])
            paths[category] = points
            linesegments!(ax,points;color=CATEGORY_STYLES[category][3],linewidth=2.6,
                linestyle=category == :L ? :dot : category == :RL ? :dash : :solid,visible=trails.checked)
        end
        ending = Observable(Point2f[])
        scatter!(ax,ending;marker=:xcross,color="#b6bac4",markersize=11,visible=trails.checked)
        handles[system.id] = (;position,visible,color,rotation,symbol,name,size,paths,ending)
    end
    # Compact legend over the map. The full scheme and provenance are documented in the repo.
    legendpoints = Point2f[(0.015,0.985),(0.30,0.985),(0.30,0.64),(0.015,0.64)]
    poly!(ax,legendpoints;color=(:black,0.75),space=:relative,inspectable=false)
    text!(ax,Point2f(0.028,0.965);text="KỊCH BẢN / THANG GIÓ 1 PHÚT\nL  Nhiễu động   D / SD  Áp thấp\nS / SS  Bão      EX / ×  Ngoại / tàn dư\n1 → 5  SSHWS: vàng → hồng\nNét chấm: L · Nét đứt: tàn dư",space=:relative,
        align=(:left,:top),fontsize=11,color=:white)
    summary = Observable("")
    text!(ax,Point2f(0.98,0.04);text=summary,space=:relative,align=(:right,:bottom),fontsize=12,color="#66ded0")
    function refresh!()
        now = clock[]
        states = Dict(s.id=>storm_state(s,now) for s in scenario.systems)
        selected_id = systemmenu.selection[]
        for system in scenario.systems
            h = handles[system.id]
            state = states[system.id]
            h.visible[] = state !== nothing
            if state !== nothing
                category = storm_class(state.kind,state.wind_knots)
                h.position[] = [Point2f(state.lon,state.lat)]
                h.color[] = parse(RGBAf,CATEGORY_STYLES[category][3])
                h.symbol[] = CATEGORY_STYLES[category][1]
                selected_state = get(states,selected_id,nothing)
                crowded = selected_state !== nothing && system.id != selected_id &&
                    hypot(state.lon-selected_state.lon,state.lat-selected_state.lat) < 6
                h.name[] = crowded ? system.id : system.id*"\n"*system.name
                h.size[] = system.id == selected_id ? 70f0 : 58f0
            end
            segments = history_segments(system,now)
            for category in categories
                h.paths[category][] = reduce(vcat,([Point2f(s.a),Point2f(s.b)] for s in segments if s.category == category);init=Point2f[])
            end
            final = system.samples[end]
            h.ending[] = now >= final.time ? [Point2f(final.lon,final.lat)] : Point2f[]
        end
        selected = only(filter(s -> s.id == selected_id,scenario.systems))
        state = states[selected_id]
        display_name = isempty(selected.local_name) ? selected.name : selected.name*" / "*selected.local_name
        if state === nothing
            status = now < selected.samples[1].time ? "Chưa xuất hiện tại thời điểm này." : "Không còn hoạt động / ngoài dữ liệu."
            card[] = "$(selected.id)\n$(display_name)\n$status\nNguồn: kịch bản minh họa."
        else
            category = storm_class(state.kind,state.wind_knots)
            unit = unitmenu.selection[]
            unitlabel = Dict(:kn=>"kn",:ms=>"m/s",:kmh=>"km/h",:mph=>"mph")[unit]
            pressure = state.pressure_hpa === nothing ? "chưa có dữ liệu" : @sprintf("%.1f hPa",state.pressure_hpa)
            card[] = @sprintf("%s / %s\n%s\nVị trí  %.2f° / %.2f°\nGió  %.1f %s\nÁp suất  %s\nNguồn: kịch bản minh họa.",selected.id,display_name,CATEGORY_STYLES[category][2],state.lon,state.lat,wind_value(state.wind_knots,unit),unitlabel,pressure)
        end
        count_active = count(v -> v !== nothing,values(states))
        summary[] = "$count_active hệ thống đang hoạt động / kịch bản\nQuỹ đạo: chỉ tới thời điểm đang xem"
    end
    on(clock) do _; refresh!(); end
    on(systemmenu.selection) do _; refresh!(); end
    on(unitmenu.selection) do _; refresh!(); end
    function open_selected(as_globe)
        system = only(filter(s -> s.id == systemmenu.selection[],scenario.systems))
        state = storm_state(system,clock[])
        state === nothing || on_physical((state.lon,state.lat),as_globe)
    end
    on(physical.clicks) do _; open_selected(false); end
    on(globe.clicks) do _; open_selected(true); end
    on(start.clicks) do _; on_start(minimum(s.samples[1].time for s in scenario.systems)); end
    pressed = Ref{Union{Nothing,Tuple{Float64,Float64}}}(nothing)
    on(events(ax).mousebutton,priority=3) do event
        if active[] && event.button == Mouse.left
            if event.action == Mouse.press && is_mouseinside(ax.scene)
                pressed[] = Tuple(Float64.(events(ax).mouseposition[]))
            elseif event.action == Mouse.release
                startpoint = pressed[]
                pressed[] = nothing
                pixel = events(ax).mouseposition[]
                if startpoint !== nothing && is_mouseinside(ax.scene) && sum((pixel[i]-startpoint[i])^2 for i in 1:2) <= 16
                    localpixel = pixel .- Tuple(ax.scene.viewport[].origin)
                    distances = [begin
                        state = storm_state(system,clock[])
                        state === nothing ? Inf : begin
                            projected = Makie.project(ax.scene,Point3f(state.lon,state.lat,0))
                            hypot(projected[1]-localpixel[1],projected[2]-localpixel[2])
                        end
                    end for system in scenario.systems]
                    if minimum(distances) <= 38
                        systemmenu.i_selected[] = argmin(distances)
                        return Consume(true)
                    end
                end
            end
        end
        Consume(false)
    end
    function set_active!(enabled)
        active[] = enabled
        ax.blockscene.visible[] = enabled
        ax.scene.visible[] = enabled
        for widget in widgets; widget.blockscene.visible[] = enabled; end
    end
    function animate!(phase)
        active[] || return
        for system in scenario.systems
            state = storm_state(system,clock[])
            state === nothing && continue
            handles[system.id].rotation[] = reduced.checked[] ? 0f0 : Float32((state.lat >= 0 ? 1 : -1)*phase)
        end
    end
    refresh!()
    set_active!(false)
    (;ax,active,clock,scenario,handles,systemmenu,unitmenu,trails,reduced,region,start,card,summary,
        physical,globe,refresh!,set_active!,reset!,animate!)
end
end
