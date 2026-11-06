module TerraFluxGlobe
export sphere_point, lonlat_from_point, sphere_hit, globe_geometry, globe_colors

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
end
