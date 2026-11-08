module TerraFluxVortexProfiles
export vortex_spec,vortex_column,vortex_at,reference_profile
const EARTH_RADIUS=6371000.
function vortex_spec(;lon,lat,radius_km,pressure_drop_hpa,depth=0.75)
    all(x->x isa Real && !(x isa Bool) && isfinite(x),(lon,lat,radius_km,pressure_drop_hpa,depth)) || error("Thông số xoáy phải là số hữu hạn.")
    -180<=lon<=180 && 10<=abs(lat)<=40 || error("Tâm xoáy: kinh độ −180…180°, |vĩ độ| 10…40°.")
    800<=radius_km<=3000 || error("Bán kính ngoài của xoáy: 800–3000 km.")
    radius_km*1000<=0.8EARTH_RADIUS*deg2rad(abs(lat)) || error("Vùng xoáy quá gần/đi qua xích đạo; giảm R hoặc dịch tâm ra xa.")
    5<=pressure_drop_hpa<=25 && 0.5<=depth<=1.5 || error("Trũng áp tham chiếu 5–25 hPa; độ giảm theo cao k = 0.5–1.5.")
    (;lon=Float64(lon),lat=Float64(lat),radius_km=Float64(radius_km),pressure_drop_hpa=Float64(pressure_drop_hpa),depth=Float64(depth))
end

"Dry isothermal reference: hydrostatic column plus cyclonic gradient wind on an f plane."
function vortex_column(r,sigma,spec;rotation=7.29e-5,Rd=287.05,Tref=300.)
    0<sigma<=1 || throw(ArgumentError("Sigma phải trong (0,1]."))
    R=1000spec.radius_km;x=r/R
    (r<0 || r>=R) && return (;u_theta=0.,delta_tv=0.,delta_logps=0.,y=-log(sigma),acceleration=0.)
    w=(1-x)^4*(1+4x);dw=-20x*(1-x)^3/R
    A=-log1p(-spec.pressure_drop_hpa/1000);q=A*w;k=spec.depth
    # ln sigma = -y + q*(1-exp(-k*y)); solve monotonically in [L,L+q].
    L=-log(sigma);lo=L;hi=L+q
    for _ in 1:36
        y=(lo+hi)/2
        y-q*(-expm1(-k*y))<L ? (lo=y) : (hi=y)
    end
    y=(lo+hi)/2;F=exp(-k*y)
    tv=Tref/(1-q*k*F)
    acceleration=-Rd*tv*A*F*dw
    f=abs(2rotation*sind(spec.lat))
    speed=r<=eps(R) ? 0. : 2acceleration/(sqrt(f*f+4acceleration/r)+f)
    (;u_theta=sign(spec.lat)*speed,delta_tv=tv-Tref,delta_logps=-q,y,acceleration)
end
function vortex_at(lon,lat,sigma,spec;radius=EARTH_RADIUS,kwargs...)
    # Tangent to circles about the centre on the sphere, not a map-plane spiral.
    c=(cosd(spec.lat)*cosd(spec.lon),cosd(spec.lat)*sind(spec.lon),sind(spec.lat))
    p=(cosd(lat)*cosd(lon),cosd(lat)*sind(lon),sind(lat))
    cross=(c[2]*p[3]-c[3]*p[2],c[3]*p[1]-c[1]*p[3],c[1]*p[2]-c[2]*p[1])
    sn=sqrt(sum(abs2,cross));cs=clamp(sum(c[i]*p[i] for i in 1:3),-1,1)
    r=radius*atan(sn,cs);v=vortex_column(r,sigma,spec;kwargs...)
    east=(-sind(lon),cosd(lon),0.);north=(-sind(lat)*cosd(lon),-sind(lat)*sind(lon),cosd(lat))
    u=sn<1e-12 ? 0. : v.u_theta*sum(cross[i]*east[i] for i in 1:3)/sn
    n=sn<1e-12 ? 0. : v.u_theta*sum(cross[i]*north[i] for i in 1:3)/sn
    (;u,v=n,delta_tv=v.delta_tv,delta_logps=v.delta_logps,r)
end
function reference_profile(spec)
    s=vortex_spec(;spec...)
    columns=[vortex_column(r,1.,s) for r in range(0,1000s.radius_km;length=201)]
    (;max_wind_mps=maximum(abs(c.u_theta) for c in columns),max_delta_tv=first(columns).delta_tv)
end
end
