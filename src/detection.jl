module TerraFluxDetection
using Dates
using ..TerraFluxStorms
export DetectionConfig, ModelStormSet, detect_tracks, detect_candidates, spherical_vorticity, great_circle_km,
       model_structure

Base.@kwdef struct DetectionConfig
    pressure_depth_hpa::Float64 = 2.0
    cyclonic_vorticity_s::Float64 = 1e-5
    ring_inner_km::Float64 = 750.0
    ring_outer_km::Float64 = 1500.0
    wind_radius_km::Float64 = 750.0
    separation_km::Float64 = 800.0
    min_latitude::Float64 = 5.0
    max_latitude::Float64 = 70.0
    max_speed_mps::Float64 = 35.0
    grid_tolerance_km::Float64 = 400.0
    max_link_hours::Float64 = 12.0
    max_candidates::Int = 32
    thermal_core_km::Float64 = 500.0
    thermal_anomaly_k::Float64 = 0.5
    circulation_inner_km::Float64 = 500.0
    circulation_outer_km::Float64 = 1000.0
    circulation_min_mps::Float64 = 2.0
end
struct ModelStormSet
    title::String
    provenance::String
    systems::Vector{StormSystem}
    metrics::Dict{Tuple{String,DateTime},NamedTuple}
    reports::Vector{NamedTuple}
    config::DetectionConfig
    layer::Int
    sigma::Float64
    source_path::String
end
const EARTH_RADIUS_M=6_371_000.0
wraprad(x)=mod(x+pi,2pi)-pi
function great_circle_km(lon1,lat1,lon2,lat2)
    a=sind((lat2-lat1)/2)^2+cosd(lat1)*cosd(lat2)*sind((lon2-lon1)/2)^2
    2(EARTH_RADIUS_M/1000)*asin(sqrt(clamp(a,0,1)))
end
include("structure.jl")
function validate_grid(d,c)
    length(d.lon)>=8 && length(d.lat)>=5 || error("Nhận diện cần lưới toàn cầu ít nhất 8×5 ô.")
    gaps=vcat(diff(d.lon),d.lon[1]+360-d.lon[end])
    all(>(0),gaps) && maximum(gaps)/minimum(gaps)<1.2 || error("Nhận diện hiện yêu cầu kinh độ đều, tuần hoàn toàn cầu.")
    all(diff(d.lat).>0) && all(abs.(d.lat).<90) || error("Vĩ độ phải tăng và nằm giữa hai cực.")
    all(x -> 0<x<=1,d.layers) || error("Nhận diện hiện hỗ trợ các tầng sigma trong (0,1].")
    all(diff(d.times).>Millisecond(0)) || error("Thời gian nhận diện phải tăng nghiêm ngặt.")
    0<c.ring_inner_km<c.ring_outer_km && c.wind_radius_km>0 && c.separation_km>0 &&
        c.pressure_depth_hpa>0 && c.cyclonic_vorticity_s>0 && 0<c.min_latitude<c.max_latitude<90 &&
        c.max_speed_mps>0 && c.grid_tolerance_km>=0 && c.max_link_hours>0 && c.max_candidates>0 || error("Tiêu chí nhận diện không hợp lệ.")
    0<c.thermal_core_km<c.ring_inner_km && c.thermal_anomaly_k>0 &&
        0<c.circulation_inner_km<c.circulation_outer_km && c.circulation_min_mps>0 || error("Tiêu chí cấu trúc không hợp lệ.")
    all(isfinite,getfield.(Ref(c),fieldnames(DetectionConfig))) || error("Tiêu chí phải hữu hạn.")
    !isempty(d.times) || error("Chưa có mốc thời gian.")
    nx,ny,nt=length(d.lon),length(d.lat),length(d.times)
    size(d.fields[:mslp])==(nx,ny,nt) || error("Áp suất không khớp lưới/thời gian.")
    for f in (:u,:v)
        size(d.fields[f])==(nx,ny,length(d.layers),nt) || error("Gió không khớp lưới/tầng/thời gian.")
    end
    !haskey(d.fields,:temp) || size(d.fields[:temp])==size(d.fields[:u]) || error("Nhiệt độ không khớp lưới/tầng/thời gian.")
end

"Relative vertical vorticity on a sphere, central differences on nonuniform latitude."
function spherical_vorticity(u,v,lon,lat)
    nx,ny=size(u)
    result=fill(NaN,nx,ny)
    phi=deg2rad.(lat)
    for j in 2:ny-1,i in 1:nx
        im,ip=mod1(i-1,nx),mod1(i+1,nx)
        h1,h2=phi[j]-phi[j-1],phi[j+1]-phi[j]
        dlambda=mod(deg2rad(lon[ip]-lon[im]),2pi)
        dvdlam=(v[ip,j]-v[im,j])/dlambda
        ducos=(-h2/(h1*(h1+h2)))*u[i,j-1]*cos(phi[j-1]) +
            ((h2-h1)/(h1*h2))*u[i,j]*cos(phi[j]) +
            (h1/(h2*(h1+h2)))*u[i,j+1]*cos(phi[j+1])
        result[i,j]=(dvdlam-ducos)/(EARTH_RADIUS_M*cos(phi[j]))
    end
    result
end

function candidates_at(d,t,c,layer)
    p=d.fields[:mslp][:,:,t]
    u=d.fields[:u][:,:,layer,t]
    v=d.fields[:v][:,:,layer,t]
    zeta=spherical_vorticity(u,v,d.lon,d.lat)
    nx,ny=size(p)
    candidates=NamedTuple[]
    for j in 2:ny-1,i in 1:nx
        latitude=d.lat[j]
        c.min_latitude<=abs(latitude)<=c.max_latitude || continue
        center=Float64(p[i,j])
        isfinite(center) && center>0 || continue
        vort=sign(latitude)*zeta[i,j]
        isfinite(vort) && vort>=c.cyclonic_vorticity_s || continue
        neighbors=[p[mod1(i+di,nx),j+dj] for di in -1:1 for dj in -1:1 if di!=0 || dj!=0]
        all(isfinite,neighbors) && all(>=(center),neighbors) && any(>(center),neighbors) || continue
        # Deterministic owner of an equal-pressure adjacent plateau.
        any(p[mod1(i+di,nx),j+dj]==center && (j+dj-1)*nx+mod1(i+di,nx)<(j-1)*nx+i
            for di in -1:1 for dj in -1:1 if di!=0 || dj!=0) && continue
        ring=Float64[]
        winds=Float64[]
        sectors=falses(4)
        total_ring=0
        for jj in 1:ny,ii in 1:nx
            distance=great_circle_km(d.lon[i],latitude,d.lon[ii],d.lat[jj])
            if c.ring_inner_km<=distance<=c.ring_outer_km
                total_ring+=1
                if isfinite(p[ii,jj])
                    push!(ring,Float64(p[ii,jj]))
                    east=wraprad(deg2rad(d.lon[ii]-d.lon[i]))>=0
                    north=d.lat[jj]>=latitude
                    sectors[1+Int(east)+2Int(north)]=true
                end
            end
            if distance<=c.wind_radius_km && isfinite(u[ii,jj]) && isfinite(v[ii,jj])
                push!(winds,hypot(Float64(u[ii,jj]),Float64(v[ii,jj])))
            end
        end
        length(ring)>=8 && length(ring)>=0.8total_ring && all(sectors) && !isempty(winds) || continue
        depth=sum(ring)/length(ring)-center
        depth>=c.pressure_depth_hpa || continue
        push!(candidates,(lon=Float64(d.lon[i]),lat=Float64(latitude),pressure=center,
            depth=depth,vorticity=zeta[i,j],wind_mps=maximum(winds),i=i,j=j))
    end
    sort!(candidates;by=x -> (x.pressure,-x.depth,x.j,x.i))
    kept=NamedTuple[]
    for candidate in candidates
        all(other -> great_circle_km(candidate.lon,candidate.lat,other.lon,other.lat)>=c.separation_km,kept) && push!(kept,candidate)
    end
    found=length(kept)
    resize!(kept,min(length(kept),c.max_candidates))
    kept=[merge(candidate,model_structure(d,t,candidate;config=c,layer)) for candidate in kept]
    kept,(valid_pressure=count(isfinite,p),valid_wind=count(k->isfinite(u[k]) && isfinite(v[k]),eachindex(u,v)),total_cells=length(p),found=found,kept=length(kept),capped=found>length(kept))
end

function detect_candidates(d,t;config=DetectionConfig())
    validate_grid(d,config)
    candidates_at(d,t,config,argmax(d.layers))
end

"Past-only, deterministic nearest-pair linking. Missing detections break identity; no gap fill."
function detect_tracks(d;config=DetectionConfig())
    validate_grid(d,config)
    layer=argmax(d.layers)
    systems=StormSystem[]
    metrics=Dict{Tuple{String,DateTime},NamedTuple}()
    reports=NamedTuple[]
    previous=Int[]
    for (t,now) in enumerate(d.times)
        candidates,report=candidates_at(d,t,config,layer)
        push!(reports,merge(report,(time=now,)))
        pairs=Tuple{Float64,Int,Int}[]
        for index in previous
            sample=systems[index].samples[end]
            hours=Dates.value(now-sample.time)/3_600_000
            hours<=config.max_link_hours || continue
            for (k,candidate) in enumerate(candidates)
                sign(candidate.lat)==sign(sample.lat) || continue
                distance=great_circle_km(sample.lon,sample.lat,candidate.lon,candidate.lat)
                distance<=config.max_speed_mps*hours*3.6+config.grid_tolerance_km && push!(pairs,(distance,index,k))
            end
        end
        sort!(pairs)
        assignments=Dict{Int,Int}()
        matched=Set{Int}()
        for (_,index,k) in pairs
            !haskey(assignments,k) && !(index in matched) || continue
            assignments[k]=index
            push!(matched,index)
        end
        for index in previous
            if !(index in matched)
                old=systems[index].samples[end]
                push!(systems[index].samples,StormSample(now,old.lon,old.lat,old.wind_knots,old.pressure_hpa,old.kind,false,old.radius_km))
            end
        end
        current=Int[]
        for (k,candidate) in enumerate(candidates)
            index=get(assignments,k,0)
            if index==0
                id="MODEL-"*lpad(string(length(systems)+1),4,'0')
                push!(systems,StormSystem(id,"Ứng viên xoáy","",StormSample[]))
                index=length(systems)
            end
            system=systems[index]
            kind=candidate.thermal_core==:warm ? "model_warm" : candidate.thermal_core==:cold ? "model_cold" : "model_low"
            sample=StormSample(now,candidate.lon,candidate.lat,candidate.wind_mps*3600/1852,candidate.pressure,kind,true,candidate.radius_km)
            push!(system.samples,sample)
            metrics[(system.id,now)]=merge((pressure_depth_hpa=candidate.depth,vorticity_s=candidate.vorticity,
                wind_mps=candidate.wind_mps,layer=layer,sigma=Float64(d.layers[layer]),i=candidate.i,j=candidate.j),
                (;candidate.thermal_core,candidate.lower_anomaly_k,candidate.upper_anomaly_k,
                    candidate.lower_sigmas,candidate.upper_sigmas,candidate.thermal_reason,
                    candidate.circulation,candidate.quadrant_wind_mps,candidate.radius_km,candidate.radius_censored,
                    candidate.radius_profile_mps,candidate.radius_bins_km))
            push!(current,index)
        end
        previous=current
    end
    ModelStormSet("Ứng viên từ trường áp suất/gió","model_detection",systems,metrics,reports,
        config,layer,Float64(d.layers[layer]),String(d.path))
end
end
