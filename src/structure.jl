# Included in TerraFluxDetection. These are exploratory structure diagnostics,
# not the Hart cyclone phase space or an operational NOAA tropical classifier.
function thermal_anomaly(d,t,layer,core,ring)
    T=@view d.fields[:temp][:,:,layer,t]
    valid_core=filter(p->isfinite(T[p.i,p.j]),core)
    valid_ring=filter(p->isfinite(T[p.i,p.j]),ring)
    length(valid_core)>=3 && length(valid_core)>=0.8length(core) &&
        length(valid_ring)>=8 && length(valid_ring)>=0.8length(ring) &&
        length(unique(p.quadrant for p in valid_ring))==4 || return nothing
    # Fit T=a+b*x+c*y in the surrounding ring. Removing a local background
    # gradient prevents a simple warm/cold north-south gradient becoming a core.
    meanof(points,f)=sum(p.weight*f(p) for p in points)/sum(p.weight for p in points)
    x,y,temperature=(meanof(valid_ring,f) for f in (p->p.x,p->p.y,p->Float64(T[p.i,p.j])))
    xx=meanof(valid_ring,p->(p.x-x)^2)
    yy=meanof(valid_ring,p->(p.y-y)^2)
    xy=meanof(valid_ring,p->(p.x-x)*(p.y-y))
    xt=meanof(valid_ring,p->(p.x-x)*(Float64(T[p.i,p.j])-temperature))
    yt=meanof(valid_ring,p->(p.y-y)*(Float64(T[p.i,p.j])-temperature))
    determinant=xx*yy-xy^2
    determinant>1e-8 || return nothing
    b,c=(xt*yy-yt*xy)/determinant,(yt*xx-xt*xy)/determinant
    meanof(valid_core,p->Float64(T[p.i,p.j])-(temperature+b*(p.x-x)+c*(p.y-y)))
end

"Read-only thermal-core and four-quadrant circulation diagnostics at one pressure candidate."
function model_structure(d,t,candidate;config=DetectionConfig(),layer=argmax(d.layers))
    c=config
    core,ring=NamedTuple[],NamedTuple[]
    windsum=zeros(4);windweight=zeros(4);windcount=zeros(Int,4);totalwind=zeros(Int,4)
    centerphi=deg2rad(candidate.lat)
    for j in eachindex(d.lat),i in eachindex(d.lon)
        distance=great_circle_km(candidate.lon,candidate.lat,d.lon[i],d.lat[j])
        distance<=max(c.ring_outer_km,c.circulation_outer_km) || continue
        delta=wraprad(deg2rad(d.lon[i]-candidate.lon))
        x=(EARTH_RADIUS_M/1e6)*cos(centerphi)*delta
        y=(EARTH_RADIUS_M/1e6)*deg2rad(d.lat[j]-candidate.lat)
        quadrant=1+Int(x>=0)+2Int(y>=0)
        weight=cosd(d.lat[j])
        point=(;i,j,x,y,quadrant,weight)
        distance<=c.thermal_core_km && push!(core,point)
        c.ring_inner_km<=distance<=c.ring_outer_km && push!(ring,point)
        if c.circulation_inner_km<=distance<=c.circulation_outer_km
            totalwind[quadrant]+=1
            u,v=d.fields[:u][i,j,layer,t],d.fields[:v][i,j,layer,t]
            isfinite(u) && isfinite(v) || continue
            phi=deg2rad(d.lat[j])
            # Bearing from the sample towards the center in the sample's local
            # east/north frame; its perpendicular is cyclonic in the NH.
            bearing=atan(-sin(delta)*cos(centerphi),cos(phi)*sin(centerphi)-sin(phi)*cos(centerphi)*cos(delta))
            tangential=sign(candidate.lat)*(u*cos(bearing)-v*sin(bearing))
            windsum[quadrant]+=weight*tangential
            windweight[quadrant]+=weight
            windcount[quadrant]+=1
        end
    end
    quadrants=ntuple(q->windcount[q]>=2 && windcount[q]>=0.8totalwind[q] ? windsum[q]/windweight[q] : nothing,4)
    circulation=any(isnothing,quadrants) ? :unknown : all(v->v>=c.circulation_min_mps,quadrants) ? :supported : :not_supported
    lower=findall(s->0.4<=s<=0.75,d.layers)
    upper=findall(s->0.2<=s<0.4,d.layers)
    function band_anomaly(indices)
        isempty(indices) && return nothing
        values=[thermal_anomaly(d,t,k,core,ring) for k in indices]
        any(isnothing,values) ? nothing : sum(values)/length(values)
    end
    has_temperature=haskey(d.fields,:temp)
    lo=has_temperature ? band_anomaly(lower) : nothing
    hi=has_temperature ? band_anomaly(upper) : nothing
    thermal=lo===nothing || hi===nothing ? :unknown :
        lo>=c.thermal_anomaly_k && hi>=c.thermal_anomaly_k ? :warm :
        lo<=-c.thermal_anomaly_k && hi<=-c.thermal_anomaly_k ? :cold : :mixed
    reason=!has_temperature ? "Thiếu trường nhiệt độ." : isempty(lower) || isempty(upper) ?
        "Thiếu tầng sigma trong một trong hai dải nhiệt." : thermal==:unknown ?
        "Thiếu ô nhiệt độ hợp lệ quanh tâm hoặc vành nền." : thermal==:mixed ?
        "Dị thường hai dải chưa cùng vượt ngưỡng ấm/lạnh." : "Dị thường hai dải cùng vượt ngưỡng thử nghiệm."
    merge((;thermal_core=thermal,lower_anomaly_k=lo,upper_anomaly_k=hi,
        lower_sigmas=Float64.(d.layers[lower]),upper_sigmas=Float64.(d.layers[upper]),
        thermal_reason=reason,circulation,quadrant_wind_mps=quadrants),vortex_extent(d,t,candidate;config=c,layer))
end

"Outer radius of consecutive four-quadrant cyclonic-wind annuli; not R34 or a forecast cone."
function vortex_extent(d,t,center;config=DetectionConfig(),layer=argmax(d.layers))
    radii=collect(500.:250.:1750.)
    total=zeros(Int,length(radii),4);count=zeros(Int,size(total))
    sums=zeros(size(total));weights=zeros(size(total))
    phi0=deg2rad(center.lat)
    for j in eachindex(d.lat),i in eachindex(d.lon)
        distance=great_circle_km(center.lon,center.lat,d.lon[i],d.lat[j])
        250<=distance<=2000 || continue
        dl=wraprad(deg2rad(d.lon[i]-center.lon))
        q=1+Int(dl>=0)+2Int(d.lat[j]>=center.lat)
        u,v=d.fields[:u][i,j,layer,t],d.fields[:v][i,j,layer,t]
        valid=isfinite(u) && isfinite(v)
        phi=deg2rad(d.lat[j])
        beta=atan(-sin(dl)*cos(phi0),cos(phi)*sin(phi0)-sin(phi)*cos(phi0)*cos(dl))
        vt=valid ? sign(center.lat)*(u*cos(beta)-v*sin(beta)) : NaN
        w=cos(phi)
        for k in eachindex(radii)
            abs(distance-radii[k])<=250 || continue
            total[k,q]+=1
            if valid
                count[k,q]+=1;sums[k,q]+=w*vt;weights[k,q]+=w
            end
        end
    end
    profile=Union{Nothing,Float64}[]
    for k in eachindex(radii)
        complete=all(q->count[k,q]>=2 && count[k,q]>=0.8total[k,q],1:4)
        push!(profile,complete ? minimum(sums[k,:]./weights[k,:]) : nothing)
    end
    radius=nothing;censored=false;previous=0
    for k in eachindex(radii)
        value=profile[k]
        if value!==nothing && value>=config.circulation_min_mps
            radius=radii[k];previous=k;censored=k==length(radii)
        elseif radius!==nothing
            if value===nothing
                censored=true
            else
                last=profile[previous]
                fraction=clamp((last-config.circulation_min_mps)/(last-value),0,1)
                radius=radii[previous]+fraction*(radii[k]-radii[previous])
            end
            break
        end
    end
    (;radius_km=radius===nothing ? nothing : 50round(radius/50),radius_censored=censored,
        radius_profile_mps=profile,radius_bins_km=radii)
end
