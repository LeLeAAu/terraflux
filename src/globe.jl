module TerraFluxGlobe
export sphere_point, lonlat_from_point, sphere_hit, globe_geometry, globe_colors,
       smooth_globe_geometry, smooth_globe_colors, smooth_sphere_lines

sphere_point(lon, lat; radius=1.0) = (radius*cosd(lat)*cosd(lon), radius*cosd(lat)*sind(lon), radius*sind(lat))
function lonlat_from_point(p)
    r = sqrt(sum(abs2, p))
    r > 0 || throw(ArgumentError("Không thể xác định tọa độ tại tâm cầu."))
    (mod(rad2deg(atan(p[2],p[1]))+180,360)-180, rad2deg(asin(clamp(p[3]/r,-1,1))))
end

"Closest forward intersection with a unit sphere; an empty-sky click returns nothing."
function sphere_hit(origin, direction)
    a = sum(abs2, direction)
    a > 0 || return nothing
    b = 2sum(origin[i]*direction[i] for i in 1:3)
    c = sum(abs2, origin)-1
    discriminant = b*b-4a*c
    discriminant < 0 && return nothing
    roots = ((-b-sqrt(discriminant))/(2a), (-b+sqrt(discriminant))/(2a))
    positive = filter(>=(0), roots)
    isempty(positive) && return nothing
    t = minimum(positive)
    lonlat_from_point(ntuple(i -> origin[i]+t*direction[i],3))
end

"One independently colored quad per output cell, including the poles and periodic seam."
function globe_geometry(lon, lat)
    xedges = vcat((lon[1]+lon[end]-360)/2, (lon[1:end-1]+lon[2:end])/2,
        (lon[1]+lon[end]+360)/2)
    yedges = vcat(-90.0, (lat[1:end-1]+lat[2:end])/2, 90.0)
    points = NTuple{3,Float64}[]
    faces = NTuple{3,Int}[]
    for j in eachindex(lat), i in eachindex(lon)
        n = length(points)
        for (x,y) in ((xedges[i],yedges[j]),(xedges[i+1],yedges[j]),
                      (xedges[i+1],yedges[j+1]),(xedges[i],yedges[j+1]))
            push!(points,sphere_point(x,y))
        end
        push!(faces,(n+1,n+2,n+3),(n+1,n+3,n+4))
    end
    points,faces
end
globe_colors(a) = repeat(vec(a); inner=4)

"Shared fine mesh for display interpolation; original cells remain the sampling data."
function smooth_globe_geometry(lon,lat;factor=3)
    xs=collect(range(lon[1],lon[1]+360;length=factor*length(lon)+1))
    ys=collect(range(-90,90;length=factor*length(lat)+1))
    points=[sphere_point(x,y) for y in ys for x in xs]
    faces=NTuple{3,Int}[]
    nx=length(xs)
    for j in 1:length(ys)-1,i in 1:nx-1
        n=(j-1)*nx+i
        push!(faces,(n,n+1,n+nx+1),(n,n+nx+1,n+nx))
    end
    samples=NamedTuple[]
    for y in ys,x in xs
        i=clamp(searchsortedlast(lon,x),1,length(lon));ip=mod1(i+1,length(lon))
        width=ip==1 ? lon[1]+360-lon[i] : lon[ip]-lon[i]
        a=(x-lon[i])/width
        j=clamp(searchsortedlast(lat,y),1,length(lat)-1)
        b=clamp((y-lat[j])/(lat[j+1]-lat[j]),0,1)
        cap=y<lat[1] ? -1 : y>lat[end] ? 1 : 0
        mix=cap==-1 ? (y+90)/(lat[1]+90) : cap==1 ? (90-y)/(90-lat[end]) : 1.
        push!(samples,(;i,ip,j,a,b,cap,mix))
    end
    (;points,faces,samples)
end
function smooth_globe_colors(a,geometry)
    south=all(isfinite,a[:,1]) ? sum(a[:,1])/size(a,1) : NaN
    north=all(isfinite,a[:,end]) ? sum(a[:,end])/size(a,1) : NaN
    map(geometry.samples) do p
        if p.cap!=0
            row=p.cap<0 ? 1 : size(a,2)
            pole=p.cap<0 ? south : north
            value=(1-p.a)*a[p.i,row]+p.a*a[p.ip,row]
            return Float32((1-p.mix)*pole+p.mix*value)
        end
        Float32((1-p.b)*((1-p.a)*a[p.i,p.j]+p.a*a[p.ip,p.j])+
            p.b*((1-p.a)*a[p.i,p.j+1]+p.a*a[p.ip,p.j+1]))
    end
end
"Densify great-circle coastlines above the sphere, avoiding straight chords clipping into Earth."
function smooth_sphere_lines(lonlat;radius=1.004,max_degrees=0.5)
    points=NTuple{3,Float64}[]
    previous=nothing
    for p in lonlat
        if !all(isfinite,p)
            push!(points,(NaN,NaN,NaN));previous=nothing;continue
        end
        current=sphere_point(p[1],p[2])
        if previous!==nothing
            angle=acos(clamp(sum(previous[k]*current[k] for k in 1:3),-1,1))
            n=max(1,ceil(Int,rad2deg(angle)/max_degrees))
            for step in 1:n-1
                t=step/n
                v=angle<1e-8 ? current : ntuple(k->(sin((1-t)*angle)*previous[k]+sin(t*angle)*current[k])/sin(angle),3)
                push!(points,ntuple(k->radius*v[k],3))
            end
        end
        push!(points,ntuple(k->radius*current[k],3));previous=current
    end
    points
end
end
