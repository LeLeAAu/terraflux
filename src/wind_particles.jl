module TerraFluxWind
using Random
export WindParticles, reset_particles!, clear_trails!, step_particles!, particle_segments, velocity_at
const EARTH_M=6_371_000.0
mutable struct WindParticles
    lon::Vector{Float64}
    lat::Vector{Float64}
    age::Vector{Float64}
    history_lon::Matrix{Float64}
    history_lat::Matrix{Float64}
    lifetime::Float64
    speed::Float64
    bounds::NTuple{4,Float64}
    rng::MersenneTwister
end
function WindParticles(;count=1000,trail_steps=16,lifetime=4.,speed=72000.,seed=42)
    p=WindParticles(zeros(count),zeros(count),zeros(count),fill(NaN,count,trail_steps),
        fill(NaN,count,trail_steps),lifetime,speed,(-180.,180.,-80.,80.),MersenneTwister(seed))
    reset_particles!(p,p.bounds)
end
function respawn!(p,i)
    west,east,south,north=p.bounds
    p.lon[i]=west+rand(p.rng)*(east-west)
    p.lat[i]=asind(sind(south)+rand(p.rng)*(sind(north)-sind(south)))
    p.age[i]=0
    p.history_lon[i,:].=NaN;p.history_lat[i,:].=NaN
    p.history_lon[i,1]=p.lon[i];p.history_lat[i,1]=p.lat[i]
end
function reset_particles!(p,bounds)
    p.bounds=Float64.(bounds)
    for i in eachindex(p.lon);respawn!(p,i);p.age[i]=rand(p.rng)*p.lifetime;end
    p
end
function clear_trails!(p)
    p.history_lon.=NaN;p.history_lat.=NaN
    p.history_lon[:,1].=p.lon;p.history_lat[:,1].=p.lat
end
"Bilinear u/v in m/s, periodic only when the longitude grid actually spans the globe."
function velocity_at(d,k,t,longitude,latitude)
    d.lat[1]<=latitude<=d.lat[end] || return nothing
    nx=length(d.lon)
    periodic=abs(d.lon[end]-d.lon[1]+(d.lon[2]-d.lon[1])-360)<1e-3
    x=periodic ? mod(longitude-d.lon[1],360)+d.lon[1] : longitude
    !periodic && !(d.lon[1]<=x<=d.lon[end]) && return nothing
    i=clamp(searchsortedlast(d.lon,x),1,nx)
    ip=i==nx ? (periodic ? 1 : nx) : i+1
    j=clamp(searchsortedlast(d.lat,latitude),1,length(d.lat)-1)
    dx=ip==1 ? d.lon[1]+360-d.lon[i] : d.lon[ip]-d.lon[i]
    a=dx==0 ? 0. : (x-d.lon[i])/dx
    b=(latitude-d.lat[j])/(d.lat[j+1]-d.lat[j])
    function sample(f)
        q=d.fields[f]
        values=(q[i,j,k,t],q[ip,j,k,t],q[i,j+1,k,t],q[ip,j+1,k,t])
        all(isfinite,values) || return nothing
        (1-b)*((1-a)*values[1]+a*values[2])+b*((1-a)*values[3]+a*values[4])
    end
    u,v=sample(:u),sample(:v)
    u===nothing || v===nothing ? nothing : (u,v)
end
function step_particles!(p,d,k,t,real_dt)
    real_dt<=0 && return p
    dt=min(real_dt,0.1)
    model_dt=dt*p.speed
    west,east,south,north=p.bounds
    for i in eachindex(p.lon)
        p.age[i]+=dt
        if p.age[i]>p.lifetime;respawn!(p,i);continue;end
        x,y=p.lon[i],p.lat[i]
        valid=true
        for _ in 1:4
            wind=velocity_at(d,k,t,x,y)
            if wind===nothing;valid=false;break;end
            h=model_dt/4
            dx=rad2deg(wind[1]*h/(EARTH_M*cosd(y)))
            dy=rad2deg(wind[2]*h/EARTH_M)
            abs(y+dy/2)<85 || (valid=false;break)
            mid=velocity_at(d,k,t,x+dx/2,y+dy/2)
            if mid===nothing;valid=false;break;end
            x+=rad2deg(mid[1]*h/(EARTH_M*cosd(y+dy/2)))
            y+=rad2deg(mid[2]*h/EARTH_M)
            x=mod(x+180,360)-180
            abs(y)<85 || (valid=false;break)
        end
        if !valid || !(west<=x<=east && south<=y<=north)
            respawn!(p,i);continue
        end
        p.lon[i]=x;p.lat[i]=y
        for h in size(p.history_lon,2):-1:2
            p.history_lon[i,h]=p.history_lon[i,h-1];p.history_lat[i,h]=p.history_lat[i,h-1]
        end
        p.history_lon[i,1]=x;p.history_lat[i,1]=y
    end
    p
end
"Fixed-size pairs; NaNs break missing/respawn/seam segments without a map-wide chord."
function particle_segments(p)
    n=size(p.history_lon,2)
    points=fill((NaN32,NaN32),2length(p.lon)*(n-1))
    for i in eachindex(p.lon),h in 1:n-1
        a,b=p.history_lon[i,h],p.history_lon[i,h+1]
        y,z=p.history_lat[i,h],p.history_lat[i,h+1]
        if all(isfinite,(a,b,y,z)) && abs(a-b)<=180
            at=2((i-1)*(n-1)+h)-1
            points[at]=(Float32(a),Float32(y));points[at+1]=(Float32(b),Float32(z))
        end
    end
    points
end
end
