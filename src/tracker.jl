module TerraFluxTracker
using ..TerraFluxStorms
using ..TerraFluxDetection
using ..TerraFluxUIScope
using ..TerraFluxStormIcons
using GLMakie, GeoMakie, Dates, Printf
export build_tracker
const US_LEGEND="MỸ · GIÓ 1 PHÚT / 10 m\nD <34 kt · S 34–<64 kt\n1–5: SSHWS (WPAC: tương đương)\nWPAC: TY ≥64 · STY ≥130 kt\nL: áp thấp/nhiễu động · ×: tàn dư\nSD/SS cận nhiệt · EX/PT ngoại/hậu"

function build_tracker(sideposition, mapposition, timestamp; on_physical, on_start, model_provider=()->nothing,
        scenario_path=joinpath(@__DIR__,"..","scenarios","demo_storms.toml"),
        icon_style_path=joinpath(@__DIR__,"..","assets","storm_tracker","style.toml"))
    scenario = load_scenario(scenario_path)
    style = load_icon_style(icon_style_path)
    catalog=Ref{Any}(scenario)
    model_error=Ref("")
    title=Observable("STORM TRACKER / KỊCH BẢN MINH HỌA\n$(scenario.title) · Không phải nhận diện từ mô hình";ignore_equal_values=true)
    updating=Ref(false)
    elapsed = Ref(0.0)
    active = Observable(false)
    clock = Observable(timestamp)
    panel = GridLayout(sideposition;width=285,tellheight=false)
    widgets = Any[]
    add(widget) = (push!(widgets,widget);widget)
    add(Label(panel[1,1],"STORM TRACKER",fontsize=22,font=:bold,color="#66ded0",halign=:left))
    source_menu=add(Menu(panel[2,1],options=[("Kịch bản minh họa",:scenario),("Ứng viên từ mô hình",:model)],default=1,width=280))
    badge=Observable("KỊCH BẢN MINH HỌA / không phải mô hình")
    add(Label(panel[3,1],badge,fontsize=11,color="#f8c448",halign=:left,justification=:left))
    filter_menu=add(Menu(panel[4,1],options=[("Đang hoạt động",:active),("Dấu hiệu lõi ấm",:warm),
        ("Dấu hiệu lõi lạnh",:cold),("Hỗn hợp / chưa rõ",:other),("Tất cả + lịch sử",:history)],default=1,width=280))
    rowsize!(panel,4,Fixed(0))
    systemmenu = add(Menu(panel[5,1],options=[(s.id*" / "*s.name,s.id) for s in scenario.systems],default=1,width=280))
    unitmenu = add(Menu(panel[6,1],options=[("Gió: knot",:kn),("Gió: m/s",:ms),("Gió: km/h",:kmh),("Gió: mph",:mph)],default=1,width=280))
    card = Observable("")
    add(Label(panel[7,1],card,fontsize=12,halign=:left,justification=:left,tellwidth=false))
    buttons = GridLayout(panel[8,1])
    physical = add(Button(buttons[1,1],label="Trường vật lý",buttoncolor="#192332",labelcolor=:white))
    globe = add(Button(buttons[1,2],label="Địa cầu 3D",buttoncolor="#192332",labelcolor=:white))
    options = GridLayout(panel[9,1])
    trails = add(Checkbox(options[1,1],checked=true))
    add(Label(options[1,2],"Giữ lịch sử quỹ đạo",halign=:left,fontsize=13))
    reduced = add(Checkbox(options[2,1],checked=false))
    add(Label(options[2,2],"Giảm hiệu ứng / ngừng xoay",halign=:left,fontsize=13))
    region = add(Menu(panel[10,1],options=[("Tây Bắc Thái Bình Dương",:wpac),("Toàn cầu",:global)],default=1,width=280))
    start = add(Button(panel[11,1],label="Tới mốc đầu",buttoncolor="#192332",labelcolor=:white))
    note=Observable("Gió kịch bản: duy trì 1 phút / 10 m.\nChưa có ACE, ENSO và tác động.\nBiểu tượng không phải bán kính bão.")
    add(Label(panel[12,1],note,fontsize=11,color="#a6b7c8",halign=:left,justification=:left))
    rowgap!(panel,6)
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
    spiral = procedural_marker(style)
    handles = Dict{String,Any}()
    categories = (:LOW,:L,:D,:S,:C1,:C2,:C3,:C4,:C5,:SD,:SS,:EX,:POST,:RL,:UNKNOWN)
    function ensure_paths!(h,categories)
        for category in categories
            haskey(h.paths,category) && continue
            points=Observable(Point2f[])
            h.paths[category]=points
            linesegments!(ax,points;color=CATEGORY_STYLES[category][3],linewidth=2.6,
                linestyle=category == :L ? :dot : category == :RL ? :dash : :solid,visible=h.trail_visible)
        end
    end
    function ensure_handle!(system)
        path_categories=startswith(system.samples[1].kind,"model_") ? (:MODEL_LOW,:MODEL_WARM,:MODEL_COLD) : categories
        if haskey(handles,system.id)
            h=handles[system.id]
            ensure_paths!(h,path_categories)
            return h
        end
        member=Observable(true)
        history_visible=Observable(true)
        trail_visible=lift((show,in_catalog,history)->show && in_catalog && history,trails.checked,member,history_visible)
        is_model=Observable(false)
        position = Observable([Point2f(0,0)])
        visible = Observable(false)
        color = Observable(parse(RGBAf,CATEGORY_STYLES[:L][3]))
        rotation = Observable(0f0)
        symbol = Observable("L")
        name = Observable(system.id)
        label_visible=Observable(false)
        size = Observable(style.size)
        has_sprite = Observable(false)
        sprite_image = Observable(fill(RGBAf(0,0,0,0),1,1))
        procedural_visible = lift((v,s,m) -> v && !s && !m,visible,has_sprite,is_model)
        glow_visible=lift((v,m)->v && !m,visible,is_model)
        sprite_visible = lift((v,s) -> v && s,visible,has_sprite)
        symbol_visible = lift((v,s) -> v && (!s || style.show_symbol_on_sprite),visible,has_sprite)
        glowcolor = lift(c -> RGBAf(c.r,c.g,c.b,style.glow_opacity),color)
        scatter!(ax,position;color=glowcolor,markersize=lift(s -> s*style.glow_scale,size),visible=glow_visible)
        scatter!(ax,position;marker=spiral,color,markersize=size,rotation=rotation,visible=procedural_visible)
        scatter!(ax,position;marker=sprite_image,color=:white,markersize=size,rotation=rotation,visible=sprite_visible)
        scatter!(ax,position;color,markersize=lift((m,s)->m ? s : 31f0,is_model,size),
            strokecolor="#dcecf5",strokewidth=1.3,visible=lift((v,s)->v && !s,visible,has_sprite))
        text!(ax,position;text=symbol,align=(:center,:center),fontsize=lift(m->m ? 12 : 18,is_model),font=:bold,color="#091320",visible=symbol_visible)
        text!(ax,position;text=name,offset=(34,8),fontsize=15,font=:bold,color=:white,
            strokecolor=(:black,0.8),strokewidth=1.2,visible=label_visible)
        paths = Dict{Symbol,Observable{Vector{Point2f}}}()
        ending = Observable(Point2f[])
        scatter!(ax,ending;marker=:xcross,color="#b6bac4",markersize=11,visible=trail_visible)
        h=(;position,visible,color,rotation,symbol,name,size,paths,ending,has_sprite,sprite_image,member,trail_visible,
            history_visible,label_visible,is_model)
        handles[system.id]=h
        ensure_paths!(h,path_categories)
        h
    end
    for system in scenario.systems; ensure_handle!(system); end
    # Compact legend over the map. The full scheme and provenance are documented in the repo.
    legendpoints = Point2f[(0.015,0.985),(0.30,0.985),(0.30,0.64),(0.015,0.64)]
    poly!(ax,legendpoints;color=(:black,0.85),space=:relative,inspectable=false,depth_shift=-0.05f0)
    legend=Observable(US_LEGEND)
    text!(ax,Point2f(0.028,0.965);text=legend,space=:relative,
        align=(:left,:top),fontsize=11,color=:white,depth_shift=-0.06f0)
    summary = Observable("")
    text!(ax,Point2f(0.98,0.04);text=summary,space=:relative,align=(:right,:bottom),fontsize=12,color="#66ded0")
    function matches_group(metric,mode)
        mode in (:active,:history) && return true
        mode==:other ? metric.thermal_core in (:unknown,:mixed) : metric.thermal_core==mode
    end
    function listed_systems()
        catalog[] === nothing && return StormSystem[]
        source_menu.selection[] != :model && return catalog[].systems
        born=filter(s->s.samples[1].time<=clock[],catalog[].systems)
        filter_menu.selection[]==:history && return born
        filter(born) do system
            state=storm_state(system,clock[])
            state!==nothing && matches_group(catalog[].metrics[(system.id,clock[])],filter_menu.selection[])
        end
    end
    function option_label(system,is_model)
        !is_model && return system.id*" / "*system.name
        samples=filter(s->s.active && s.time<=clock[],system.samples)
        kind=last(samples).kind
        system.id*" / "*(kind=="model_warm" ? "Lõi ấm" : kind=="model_cold" ? "Lõi lạnh" : "Chưa rõ")
    end
    function refresh!()
        updating[] && return
        updating[]=true
        try
            now = clock[]
            is_model=source_menu.selection[] == :model
            if is_model
                result=model_provider()
                catalog[]=result isa ModelStormSet ? result : nothing
                model_error[]=result isa AbstractString ? result : ""
            else
                catalog[]=scenario
                model_error[]=""
            end
            # Model IDs that are born in future frames must not appear in the menu yet.
            listed=listed_systems()
            options=isempty(listed) ? [(is_model ? "Không có ứng viên phù hợp" : "Không có hệ thống",nothing)] : [(option_label(s,is_model),s.id) for s in listed]
            if systemmenu.options[] != options
                previous_id=systemmenu.selection[]
                systemmenu.is_open[]=false
                systemmenu.options[]=options
                selected_index=findfirst(option->option[2]==previous_id,options)
                systemmenu.i_selected[]=selected_index===nothing ? 1 : selected_index
            end
            systemmenu.selection[] === nothing && !isempty(listed) && (systemmenu.i_selected[]=1)
            states = Dict(s.id=>storm_state(s,now) for s in listed)
            for h in values(handles); h.member[]=false; h.visible[]=false; h.label_visible[]=false; end
            selected_id = systemmenu.selection[]
            for system in listed
                h = ensure_handle!(system)
                h.member[]=true
                h.is_model[]=is_model
                h.history_visible[]=!is_model || system.id==selected_id || filter_menu.selection[]==:history
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
                    h.name[] = is_model ? system.id*"\n"*CATEGORY_STYLES[category][2] :
                        crowded ? system.id : system.id*"\n"*system.name
                    h.label_visible[]=!is_model || system.id==selected_id
                    h.size[] = extent_icon_size(style,state.radius_km;selected=system.id==selected_id,model=is_model)
                    sprite=icon_sprite(style,category)
                    h.has_sprite[] = sprite !== nothing
                    if sprite !== nothing
                        h.sprite_image[] = icon_frame(sprite,elapsed[];reduced=reduced.checked[])
                    end
                    h.rotation[] = is_model && sprite===nothing ? 0f0 : icon_rotation(style,state.lat,elapsed[];reduced=reduced.checked[],sprite)
                end
                segments = history_segments(system,now)
                for category in keys(h.paths)
                    h.paths[category][] = reduce(vcat,([Point2f(s.a),Point2f(s.b)] for s in segments if s.category == category);init=Point2f[])
                end
                final = system.samples[end]
                h.ending[] = !final.active && now >= final.time ? [Point2f(final.lon,final.lat)] : Point2f[]
            end
            if selected_id === nothing || isempty(listed)
                card[]=!isempty(model_error[]) ? first(model_error[],220) : catalog[] === nothing ? "Đang phân tích dữ liệu..." :
                    "Không có ứng viên phù hợp\nở mốc và bộ lọc đang chọn.\nChọn nhóm khác hoặc Tới mốc đầu."
            else
                selected = only(filter(s -> s.id == selected_id,listed))
                state = states[selected_id]
                display_name = isempty(selected.local_name) ? selected.name : selected.name*" / "*selected.local_name
                if is_model && state !== nothing
                    metric=catalog[].metrics[(selected.id,now)]
                    unit=unitmenu.selection[]
                    label=Dict(:kn=>"kn",:ms=>"m/s",:kmh=>"km/h",:mph=>"mph")[unit]
                    anomaly(v)=v===nothing ? "thiếu" : @sprintf("%+.2f",v)
                    circulation=metric.circulation==:supported ? "4/4 phía" : metric.circulation==:unknown ? "thiếu dữ liệu" : "chưa đạt"
                    category=storm_class(state.kind,state.wind_knots)
                    extent=state.radius_km===nothing ? "R xoáy: chưa xác định" : "R xoáy $(metric.radius_censored ? "≥" : "≈") $(round(Int,state.radius_km)) km"
                    card[]=@sprintf("%s · %s\nΔT giữa/trên: %s / %s K\nGió xoáy: %s · %s\nÔ tâm %.2f° / %.2f°\nMSLP %.2f hPa · Δp %.2f\nζ %.2e s⁻¹\nMax ô σ=%.4f: %.1f %s\nKhông phải gió 10 m / 1 phút.",selected.id,CATEGORY_STYLES[category][2],anomaly(metric.lower_anomaly_k),anomaly(metric.upper_anomaly_k),circulation,extent,state.lon,state.lat,state.pressure_hpa,metric.pressure_depth_hpa,metric.vorticity_s,catalog[].sigma,wind_value(state.wind_knots,unit),label)
                elseif state === nothing
                    status = now < selected.samples[1].time ? "Chưa xuất hiện tại thời điểm này." : (is_model ? "Không đạt tiêu chí ở mốc này." : "Không còn hoạt động / ngoài dữ liệu.")
                    card[] = "$(selected.id)\n$(display_name)\n$status\nNguồn: $(is_model ? "mô hình" : "kịch bản minh họa")."
                else
                    unit = unitmenu.selection[]
                    unitlabel = Dict(:kn=>"kn",:ms=>"m/s",:kmh=>"km/h",:mph=>"mph")[unit]
                    pressure = state.pressure_hpa === nothing ? "chưa có dữ liệu" : @sprintf("%.1f hPa",state.pressure_hpa)
                    card[] = @sprintf("%s / %s\n%s\nVị trí  %.2f° / %.2f°\nGió  %.1f %s\nÁp suất  %s\nNguồn: kịch bản minh họa.",selected.id,display_name,storm_description(selected,state),state.lon,state.lat,wind_value(state.wind_knots,unit),unitlabel,pressure)
                end
            end
            count_active = count(v -> v !== nothing,values(states))
            if is_model
                badge[]="ỨNG VIÊN TỪ DỮ LIỆU MÔ HÌNH"
                title[]="STORM TRACKER / ỨNG VIÊN XOÁY MÔ HÌNH\nPhân nhóm lõi nhiệt + gió · Không gán cấp bão SSHWS"
                note[]="Chỉ nhãn/quỹ đạo tâm đang chọn.\nTất cả + lịch sử: hiện cả track cũ.\nW/C là dấu hiệu, chưa phải cấp bão."
                if catalog[] !== nothing
                    c=catalog[].config
                    legend[]=@sprintf("CẤU TRÚC MÔ HÌNH / SƠ BỘ\nW: lõi ấm · C: lõi lạnh\nHai dải ΔT cùng ≥ %.1f K / ≤ −%.1f K\nL?: hỗn hợp hoặc thiếu dữ liệu\nGió 4 phía: xem thẻ · Không SSHWS\n×: mất tiêu chí, không suy ra tan",c.thermal_anomaly_k,c.thermal_anomaly_k)
                    reportindex=findfirst(==(now),getfield.(catalog[].reports,:time))
                    if reportindex === nothing
                        summary[]="Không có dữ liệu mô hình tại mốc này."
                    else
                        report=catalog[].reports[reportindex]
                        current_metrics=[metric for ((_,time),metric) in catalog[].metrics if time==now]
                        warm=count(m->m.thermal_core==:warm,current_metrics)
                        cold=count(m->m.thermal_core==:cold,current_metrics)
                        summary[]="Hiện $count_active/$(report.kept) tâm · W $warm / C $cold / L? $(report.kept-warm-cold)\nÔ hữu hạn: P $(report.valid_pressure)/$(report.total_cells) · gió $(report.valid_wind)/$(report.total_cells)"*(report.capped ? " · đã giới hạn số tâm" : "")
                    end
                else
                    legend[]="ỨNG VIÊN MÔ HÌNH / L?\nChờ phân tích dữ liệu áp suất/gió.\nKhông phân loại bão nhiệt đới."
                    summary[]=isempty(model_error[]) ? "Đang phân tích..." : "Không thể phân tích dữ liệu này."
                end
            else
                badge[]="KỊCH BẢN MINH HỌA / không phải mô hình"
                title[]="STORM TRACKER / KỊCH BẢN MINH HỌA\n$(scenario.title) · Không phải nhận diện từ mô hình"
                note[]="Gió kịch bản: duy trì 1 phút / 10 m.\nChưa có ACE, ENSO và tác động.\nBiểu tượng không phải bán kính bão."
                legend[]=US_LEGEND
                summary[]="$count_active hệ thống đang hoạt động / kịch bản\nQuỹ đạo: chỉ tới thời điểm đang xem"
            end
        finally
            updating[]=false
        end
    end
    on(source_menu.selection) do source
        systemmenu.is_open[]=false
        filter_menu.is_open[]=false
        rowsize!(panel,4,Fixed(source==:model ? 34 : 0))
        filter_menu.blockscene.visible[]=active[] && source==:model
        region.i_selected[]=source == :model ? 2 : 1
        refresh!()
    end
    on(clock) do _; refresh!(); end
    on(filter_menu.selection) do _; refresh!(); end
    function poll_model!()
        source_menu.selection[] == :model || return
        result=model_provider()
        if result isa ModelStormSet && result !== catalog[] || result isa AbstractString && result != model_error[]
            refresh!()
        end
    end
    on(systemmenu.selection) do _; refresh!(); end
    on(unitmenu.selection) do _; refresh!(); end
    function open_selected(as_globe)
        catalog[] === nothing && return
        selected_systems=filter(s -> s.id == systemmenu.selection[],catalog[].systems)
        isempty(selected_systems) && return
        system=only(selected_systems)
        state = storm_state(system,clock[])
        state === nothing || on_physical((state.lon,state.lat),as_globe)
    end
    on(physical.clicks) do _; open_selected(false); end
    on(globe.clicks) do _; open_selected(true); end
    on(start.clicks) do _
        catalog[] === nothing && return
        if source_menu.selection[]==:model
            times=[time for ((_,time),metric) in catalog[].metrics if matches_group(metric,filter_menu.selection[])]
            isempty(times) ? (card[]="Không có ứng viên thuộc nhóm này\ntrong tệp/phiên hiện có.") : on_start(minimum(times))
        elseif !isempty(catalog[].systems)
            on_start(minimum(s.samples[1].time for s in catalog[].systems))
        end
    end
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
                    end for system in listed_systems()]
                    if !isempty(distances) && minimum(distances) <= 38
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
        for widget in widgets
            widget.blockscene.visible[]=enabled && (widget !== filter_menu || source_menu.selection[]==:model)
        end
    end
    function animate!(seconds)
        elapsed[] = seconds
        active[] || return
        for system in (catalog[] === nothing ? StormSystem[] : catalog[].systems)
            haskey(handles,system.id) || continue
            state = storm_state(system,clock[])
            state === nothing && continue
            handle=handles[system.id]
            handle.visible[] || continue
            sprite=icon_sprite(style,storm_class(state.kind,state.wind_knots))
            rotation=handle.is_model[] && sprite===nothing ? 0f0 : icon_rotation(style,state.lat,seconds;reduced=reduced.checked[],sprite)
            handle.rotation[] != rotation && (handle.rotation[] = rotation)
            if sprite !== nothing
                image=icon_frame(sprite,seconds;reduced=reduced.checked[])
                handle.sprite_image[] !== image && (handle.sprite_image[] = image)
            end
        end
    end
    scope_widget_inputs!(widgets)
    refresh!()
    set_active!(false)
    (;ax,active,clock,scenario,catalog,source_menu,filter_menu,title,poll_model!,style,handles,systemmenu,unitmenu,trails,reduced,region,start,card,summary,legend,listed_systems,
        physical,globe,refresh!,set_active!,reset!,animate!)
end
end
