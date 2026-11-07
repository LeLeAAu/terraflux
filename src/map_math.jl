module TerraFluxMapMath
using Dates
export solar_direction, night_strength, radius_outline
"Approximate Earth solar direction for the simulation's UTC DateTime, not the wall clock."
function solar_direction(t::DateTime)
    h=hour(t)+minute(t)/60+second(t)/3600
    gamma=2pi/365*(dayofyear(t)-1+(h-12)/24)
    eq=229.18*(0.000075+0.001868cos(gamma)-0.032077sin(gamma)-0.014615cos(2gamma)-0.040849sin(2gamma))
    decl=0.006918-0.399912cos(gamma)+0.070257sin(gamma)-0.006758cos(2gamma)+0.000907sin(2gamma)-0.002697cos(3gamma)+0.00148sin(3gamma)
    longitude=deg2rad(180-15h-eq/4)
    (cos(decl)*cos(longitude),cos(decl)*sin(longitude),sin(decl))
end
function night_strength(lon,lat,sun)
    dot=sind(lat)*sun[3]+cosd(lat)*(cosd(lon)*sun[1]+sind(lon)*sun[2])
    clamp(-dot/0.1,0,1)
end
function radius_outline(lon,lat,radius_km;n=96)
    delta=radius_km/6371
    phi,lambda=deg2rad(lat),deg2rad(lon)
    points=Tuple{Float64,Float64}[]
    for bearing in range(0,2pi;length=n+1)
        y=asin(clamp(sin(phi)*cos(delta)+cos(phi)*sin(delta)*cos(bearing),-1,1))
        x=lambda+atan(sin(bearing)*sin(delta)*cos(phi),cos(delta)-sin(phi)*sin(y))
        push!(points,(mod(rad2deg(x)+180,360)-180,rad2deg(y)))
    end
    points
end
end
