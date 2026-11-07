module TerraFluxMapLayers
using GLMakie,Dates,Printf
using ..TerraFluxData, ..TerraFluxGlobe, ..TerraFluxMapMath
using ..TerraFluxStorms, ..TerraFluxDetection, ..TerraFluxStormIcons, ..TerraFluxWeatherStyle
export build_map_layers
const CITIES=[("Hà Nội",105.85,21.03),("TP HCM",106.7,10.8),("Bangkok",100.5,13.75),
    ("Manila",120.98,14.6),("Tokyo",139.69,35.69),("Seoul",126.98,37.56),
    ("Beijing",116.4,39.9),("Taipei",121.56,25.04),("Sapporo",141.35,43.06),
    ("Guam",144.79,13.44),("Honolulu",-157.86,21.31),("New Delhi",77.21,28.61),
    ("Jakarta",106.8,-6.2),("Sydney",151.2,-33.87),("Paris",2.35,48.86),("New York",-74.0,40.71)]

function build_map_layers(ax,globe,geometry,mode;systems,labels,values,night,style)
    catalog=Ref{Any}(nothing);active=Ref(NamedTuple[]);highlight=Ref{Union{Nothing,String}}(nothing)
    capacity=256;omitted=Ref(0)
    positions=Observable(fill(Point2f(NaN),capacity));sphere_positions=Observable(fill(Point3f(NaN),capacity))
    colors=Observable(fill(RGBAf(0,0,0,0),capacity));sizes=Observable(fill(20f0,capacity))
    symbols=Observable(fill("",capacity))
    visible2d=lift((s,m)->s && m==:map,systems,mode)
    visible3d=lift((s,m)->s && m==:globe,systems,mode)
    scatter!(ax,positions;color=colors,markersize=sizes,strokecolor=:white,strokewidth=1.2,visible=visible2d,depth_shift=-0.02f0)
    text!(ax,positions;text=symbols,align=(:center,:center),font=:bold,fontsize=12,color=:black,visible=visible2d,depth_shift=-0.025f0)
    scatter!(globe,sphere_positions;color=colors,markersize=sizes,strokecolor=:white,strokewidth=1.2,visible=visible3d)
    text!(globe,sphere_positions;text=symbols,align=(:center,:center),font=:bold,fontsize=12,color=:black,visible=visible3d)
    ring=Observable(Point2f[]);sphere_ring=Observable(Point3f[])
    linesegments!(ax,ring;color=(:white,0.9),linewidth=1.5,linestyle=:dash,visible=visible2d,depth_shift=-0.018f0)
    lines!(globe,sphere_ring;color=(:white,0.9),linewidth=1.5,linestyle=:dash,visible=visible3d)
    paths=Dict{Symbol,Any}()
    for (category,(_,_,color)) in CATEGORY_STYLES
        p=Observable(Point2f[]);q=Observable(Point3f[])
        linesegments!(ax,p;color,linewidth=2.1,visible=visible2d,depth_shift=-0.017f0)
        linesegments!(globe,q;color,linewidth=2.1,visible=visible3d)
        paths[category]=(p,q)
    end
    city_text=Observable(fill("",length(CITIES)))
    city_positions=Observable([Point3f(sphere_point(c[2],c[3];radius=1.014)) for c in CITIES])
    city2=lift((l,v,m)->(l||v) && m==:map,labels,values,mode)
    city3=lift((l,v,m)->(l||v) && m==:globe,labels,values,mode)
    text!(ax,[Point2f(c[2],c[3]) for c in CITIES];text=city_text,fontsize=11,offset=(4,4),
        color=:white,strokecolor=:black,strokewidth=1,visible=city2,depth_shift=-0.03f0)
    text!(globe,city_positions;text=city_text,fontsize=11,offset=(4,4),color=:white,
        strokecolor=:black,strokewidth=1,visible=city3)
    xs=collect(-180.:1.:180.);ys=collect(-90.:1.:90.)
    night_image=Observable(fill(RGBAf(0,0,0,0),length(xs),length(ys)))
    image!(ax,(-180.,180.),(-90.,90.),night_image;interpolate=true,
        visible=lift((n,m)->n && m==:map,night,mode),depth_shift=-0.001f0)
    night3=Observable(fill(RGBAf(0,0,0,0),length(geometry.points)))
    mesh!(globe,[Point3f(1.002 .* p) for p in geometry.points],
        [Makie.GeometryBasics.TriangleFace(f...) for f in geometry.faces];color=night3,
        shading=NoShading,transparency=true,visible=lift((n,m)->n && m==:globe,night,mode))
    camera=cameracontrols(globe.scene)
    function front_positions!()
        eye=camera.eyeposition[]
        points=fill(Point3f(NaN),capacity)
        for (i,item) in enumerate(active[])
            unit=sphere_point(item.state.lon,item.state.lat)
            sum(unit[k]*eye[k] for k in 1:3)>1 && (points[i]=Point3f(1.016 .* unit))
        end
        sphere_positions[]=points
        city_positions[]=[begin
            unit=sphere_point(c[2],c[3]);sum(unit[k]*eye[k] for k in 1:3)>1 ? Point3f(1.014 .* unit) : Point3f(NaN)
        end for c in CITIES]
    end
    on(_->front_positions!(),camera.eyeposition)
    function highlight!(id,now)
        highlight[]=id
        item=findfirst(x->x.system.id==id,active[])
        ring[]=Point2f[];sphere_ring[]=Point3f[]
        for (p,q) in Base.values(paths);p[]=Point2f[];q[]=Point3f[];end
        item===nothing && return
        entry=active[][item];st=entry.state
        if st.radius_km!==nothing
            boundary=radius_outline(st.lon,st.lat,st.radius_km)
            pairs=Point2f[]
            for k in 1:length(boundary)-1
                abs(boundary[k+1][1]-boundary[k][1])<=180 && append!(pairs,[Point2f(boundary[k]),Point2f(boundary[k+1])])
            end
            ring[]=pairs
            sphere_ring[]=[Point3f(sphere_point(p...;radius=1.012)) for p in boundary]
        end
        history=history_segments(entry.system,now)
        for (category,(p,q)) in paths
            segments=filter(s->s.category==category,history)
            p[]=reduce(vcat,([Point2f(s.a),Point2f(s.b)] for s in segments);init=Point2f[])
            spatial=Point3f[]
            for segment in segments
                dense=smooth_sphere_lines([segment.a,segment.b];radius=1.012)
                for k in 1:length(dense)-1;append!(spatial,[Point3f(dense[k]),Point3f(dense[k+1])]);end
            end
            q[]=spatial
        end
    end
    function update!(d,framevalues,field,k,now,set)
        catalog[]=set
        entries=NamedTuple[]
        omitted[]=0
        if systems[] && set!==nothing
            for system in set.systems
                st=storm_state(system,now)
                st===nothing && continue
                if length(entries)>=capacity
                    omitted[]+=1
                    continue
                end
                push!(entries,(;system,state=st))
            end
        end
        active[]=entries
        points=fill(Point2f(NaN),capacity);cc=fill(RGBAf(0,0,0,0),capacity);ss=fill(20f0,capacity);glyphs=fill("",capacity)
        for (i,entry) in enumerate(entries)
            st=entry.state;category=storm_class(st.kind,st.wind_knots)
            points[i]=Point2f(st.lon,st.lat);cc[i]=parse(RGBAf,CATEGORY_STYLES[category][3]);glyphs[i]=CATEGORY_STYLES[category][1]
            ss[i]=extent_icon_size(style,st.radius_km;model=startswith(st.kind,"model_"))
        end
        colors[]=cc;sizes[]=ss;symbols[]=glyphs;positions[]=points
        front_positions!()
        city_text[]=[begin
            i,j=nearest_cell(d,c[2],c[3]);v=framevalues[i,j]
            number=isfinite(v) ? @sprintf("%.0f %s",v,display_unit(field)) : "thiếu"
            labels[] && values[] ? c[1]*"\n"*number : labels[] ? c[1] : values[] ? number : ""
        end for c in CITIES]
        if night[]
            sun=solar_direction(now)
            night_image[]=[RGBAf(0.01,0.02,0.05,0.33night_strength(x,y,sun)) for x in xs,y in ys]
            night3[]=[RGBAf(0.01,0.02,0.05,0.33clamp(-sum(p[i]*sun[i] for i in 1:3)/0.1,0,1)) for p in geometry.points]
        end
        highlight!(highlight[],now)
    end
    function system_at(lon,lat)
        best=nothing;score=Inf
        for item in active[]
            st=item.state
            distance=great_circle_km(lon,lat,st.lon,st.lat)
            radius=st.radius_km===nothing ? 200. : st.radius_km
            ratio=distance/radius
            if ratio<=1 && ratio<score;best=item;score=ratio;end
        end
        best
    end
    (;catalog,active,omitted,highlight,highlight!,update!,system_at,positions,sphere_positions,ring,sphere_ring,night_image,city_text)
end
end
