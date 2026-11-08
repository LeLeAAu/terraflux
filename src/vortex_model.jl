module TerraFluxVortexModel
using SpeedyWeather
using ..TerraFluxVortexProfiles
export apply_vortex!
function apply_vortex!(sim,input)
    spec=vortex_spec(;input...);vars=sim.variables;model=sim.model;g=model.geometry;S=model.spectral_transform
    vars.prognostic.clock.time_step_counter>0 && vars.prognostic.scale[]==1 || error("Tính ít nhất +6 giờ và tạm dừng trước khi tạo xoáy.")
    radius=Float64(model.planet.radius)
    1000spec.radius_km<=0.8radius*deg2rad(abs(spec.lat)) || error("Vùng xoáy đi qua xích đạo.")
    native=get_step(vars.grid.temperature,1).grid
    areas=zeros(length(g.londs))
    for (ring,omega) in zip(SpeedyWeather.RingGrids.eachring(native),SpeedyWeather.RingGrids.get_solid_angles(native))
        areas[ring].=omega*radius^2
    end
    lon=Array(g.londs);lat=Array(g.latds)
    distance=[vortex_at(lon[i],lat[i],1.,spec;radius).r for i in eachindex(lon)]
    near=findall(<(1000spec.radius_km/2),distance)
    length(near)>=8 || error("Lưới chưa đủ ô trong lõi xoáy; tăng R hoặc dùng T63/T85.")
    spacing=sqrt(sum(areas[near])/length(near))
    1000spec.radius_km>=7spacing || error("R quá nhỏ so với lưới native (cần ít nhất $(ceil(Int,7spacing/1000)) km); tăng T hoặc R.")
    p0=exp.(vec(Array(SpeedyWeather.transform(get_step(vars.prognostic.pressure,1),S))))
    vor0=copy(get_step(vars.prognostic.vorticity,1))
    T0=Array(SpeedyWeather.transform(get_step(vars.prognostic.temperature,1),S))
    q0=Array(SpeedyWeather.transform(get_step(vars.prognostic.humidity,1),S))
    U=zero(get_step(vars.grid.u,1));V=zero(get_step(vars.grid.v,1));dT=zero(get_step(vars.grid.temperature,1))
    dP=zero(get_step(vars.grid.pressure,1))
    for k in 1:g.nlayers,i in eachindex(lon)
        a=vortex_at(lon[i],lat[i],Float64(g.σ_levels_full[k]),spec;radius,
            rotation=Float64(model.planet.rotation),Rd=Float64(model.atmosphere.R_dry))
        U.data[i,k]=a.u;V.data[i,k]=a.v
        dT.data[i,k]=a.delta_tv/(1+Float64(model.atmosphere.μ_virt_temp)*q0[i,k])
        dP.data[i]=a.delta_logps
    end
    # Compute the increment in zero buffers. Upstream curl(add=true,radius!=1)
    # rescales the existing background too, so never use it to add physical winds.
    dvort=zero(get_step(vars.prognostic.vorticity,1));ddiv=zero(dvort)
    SpeedyWeather.set_vordiv!(dvort,ddiv,U,V,g,S;add=false)
    for step in 1:2
        get_step(vars.prognostic.vorticity,step).+=dvort
        SpeedyWeather.set!(sim;temperature=dT,pressure=dP,step,add=true)
    end
    # The analytic circular flow is nondivergent. Retain its rotational projection
    # and the original background divergence, dropping numerical divergence noise.
    dvort=get_step(vars.prognostic.vorticity,1)-vor0
    us=zero(dvort);vs=zero(dvort)
    SpeedyWeather.UV_from_vordiv!(us,vs,dvort,zero(dvort),S;radius)
    du=Array(SpeedyWeather.transform(us,S;unscale_coslat=true))
    dv=Array(SpeedyWeather.transform(vs,S;unscale_coslat=true))
    fit=sqrt(sum(areas.*sum((du.-U.data).^2 .+(dv.-V.data).^2;dims=2)[:])/sum(areas.*sum(U.data.^2 .+V.data.^2;dims=2)[:]))
    isfinite(fit) && fit<=0.35 || error("Chiếu phổ làm biến dạng gió xoáy quá mức (L2=$fit, radius=$(g.radius[])); tăng độ phân giải hoặc R.")
    for step in 1:2
        t=Array(SpeedyWeather.transform(get_step(vars.prognostic.temperature,step),S))
        p=exp.(Array(SpeedyWeather.transform(get_step(vars.prognostic.pressure,step),S)))
        all(isfinite,t) && minimum(t)>=100 && maximum(t)<=400 || error("Nhiệt độ sau tạo xoáy ngoài 100–400 K.")
        all(isfinite,p) && minimum(p)>10000 && maximum(p)<120000 || error("Áp suất bề mặt sau tạo xoáy không hợp lệ.")
        all(isfinite,get_step(vars.prognostic.vorticity,step)) && all(isfinite,get_step(vars.prognostic.divergence,step)) || error("Trường xoáy/phân kỳ không hữu hạn.")
    end
    p1=exp.(vec(Array(SpeedyWeather.transform(get_step(vars.prognostic.pressure,1),S))))
    T1=Array(SpeedyWeather.transform(get_step(vars.prognostic.temperature,1),S))
    thickness=diff(Float64.(g.σ_levels_half));grav=Float64(model.planet.gravity)
    column(a)=vec(a*thickness)
    mass=sum(areas.*(p1.-p0))/grav
    water=sum(areas.*(p1.-p0).*column(q0))/grav
    enthalpy=Float64(model.atmosphere.heat_capacity)/grav*sum(areas.*(p1.*column(T1).-p0.*column(T0)))
    (;projected_pressure_min_hpa=minimum(p1.-p0)/100,projected_pressure_max_hpa=maximum(p1.-p0)/100,
        projected_delta_t_min_k=minimum(T1.-T0),projected_delta_t_max_k=maximum(T1.-T0),
        air_mass_change_kg=mass,column_water_mass_change_kg=water,dry_enthalpy_change_j=enthalpy,
        projected_peak_wind_mps=maximum(hypot.(du,dv)),projected_wind_relative_l2=fit,
        native_spacing_km=spacing/1000,core_cells=length(near),reference_profile(spec)...)
end
end
