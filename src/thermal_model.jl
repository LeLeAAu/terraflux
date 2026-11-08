module TerraFluxThermalModel
using SpeedyWeather,Dates,TOML,Random
using ..TerraFluxThermalPatch
export apply_thermal!, save_checkpoint, restore_checkpoint!

function save_checkpoint(sim,path)
    rng=copy(Random.default_rng())
    try
        SpeedyWeather.jldopen(path*".tmp","w";compress=true) do f
            f["variables"]=SpeedyWeather.materialize_views(sim.variables)
            f["rng"]=rng
            f["julia"]=string(VERSION)
            f["speedyweather"]=string(pkgversion(SpeedyWeather))
        end
        mv(path*".tmp",path;force=true)
    finally
        copy!(Random.default_rng(),rng)
    end
end
function restore_checkpoint!(sim,path)
    saved=SpeedyWeather.jldopen(path,"r") do f
        f["julia"]==string(VERSION) && f["speedyweather"]==string(pkgversion(SpeedyWeather)) || error("Phiên bản checkpoint không tương thích.")
        (variables=f["variables"],rng=f["rng"])
    end
    for name in (:temperature,:humidity,:vorticity,:divergence,:pressure)
        size(getproperty(saved.variables.prognostic,name))==size(getproperty(sim.variables.prognostic,name)) || error("Lưới/tầng checkpoint không khớp mô hình.")
    end
    copy!(sim.variables,saved.variables)
    copy!(Random.default_rng(),saved.rng)
    nothing
end

function apply_thermal!(sim,spec)
    spec=thermal_spec(;spec...)
    vars=sim.variables;model=sim.model
    spec.layer<=model.geometry.nlayers || error("Tầng không có trong mô hình.")
    vars.prognostic.clock.time_step_counter>0 || error("Tính ít nhất một bước 6 giờ trước khi can thiệp.")
    vars.prognostic.scale[]==1 || error("Chỉ can thiệp giữa các đoạn đã hoàn tất.")
    g=model.geometry
    weights=patch_weight.(Array(g.londs),Array(g.latds),Ref(spec))
    count(>(0.001),weights)>=4 || error("Vùng quá nhỏ so với lưới mô hình; tăng bán kính.")
    # Change both leapfrog buffers equally, retaining their difference. run! will
    # initialize the next interval from step 1, just as in the unedited workflow.
    sigma=Float64(g.σ_levels_full[spec.layer])
    perturb=(lon,lat,s)->abs(s-sigma)<1e-6 ? spec.delta_k*patch_weight(lon,lat,spec) : 0.
    before=copy(get_step(vars.prognostic.temperature,1))
    for step in 1:2
        SpeedyWeather.set!(sim;temperature=perturb,step,add=true)
    end
    # Measure the projected increment, rather than claiming a compact region
    # remains compact after a global spherical-harmonic transform.
    projected=SpeedyWeather.transform(get_step(vars.prognostic.temperature,1)-before,model.spectral_transform)
    delta=Array(projected)
    all(isfinite,delta) || error("Nhiễu nhiệt sau chiếu phổ không hữu hạn.")
    for step in 1:2
        t=Array(SpeedyWeather.transform(get_step(vars.prognostic.temperature,step),model.spectral_transform))
        all(isfinite,t) && minimum(t)>=100 && maximum(t)<=400 || error("Nhiệt độ sau tác động ngoài khoảng thử nghiệm 100–400 K.")
    end
    native=get_step(vars.grid.temperature,1).grid
    areas=zeros(length(weights))
    for (ring,omega) in zip(SpeedyWeather.RingGrids.eachring(native),SpeedyWeather.RingGrids.get_solid_angles(native))
        areas[ring].=omega*Float64(model.planet.radius)^2
    end
    ps=exp.(vec(Array(SpeedyWeather.transform(get_step(vars.prognostic.pressure,1),model.spectral_transform))))
    thickness=Float64(g.σ_levels_half[spec.layer+1]-g.σ_levels_half[spec.layer])
    heat=Float64(model.atmosphere.heat_capacity)/Float64(model.planet.gravity)*thickness*sum(areas.*ps.*delta[:,spec.layer])
    (;requested_delta_k=spec.delta_k,projected_min_k=Float64(minimum(delta)),projected_max_k=Float64(maximum(delta)),
        native_cells=count(>(0.001),weights),sigma,heat_dry_approx_j=heat,
        global_layer_mean_delta_k=sum(areas.*delta[:,spec.layer])/sum(areas))
end
end
