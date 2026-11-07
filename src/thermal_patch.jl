module TerraFluxThermalPatch
export thermal_spec, patch_weight
function thermal_spec(;lon,lat,radius_km,layer,delta_k)
    all(x->x isa Real && isfinite(x),(lon,lat,radius_km,delta_k)) || error("Thông số vùng nhiệt phải hữu hạn.")
    -180<=lon<=180 && -90<=lat<=90 || error("Tọa độ ngoài phạm vi.")
    1000<=radius_km<=5000 || error("Bán kính thử nghiệm: 1000–5000 km.")
    layer isa Integer && 1<=layer<=32 || error("Tầng phải là số nguyên 1–32.")
    0<abs(delta_k)<=5 || error("ΔT phải khác 0 và nằm trong −5…+5 K.")
    (;lon=Float64(lon),lat=Float64(lat),radius_km=Float64(radius_km),layer=Int(layer),delta_k=Float64(delta_k))
end
function patch_weight(lon,lat,spec)
    a=sind((lat-spec.lat)/2)^2+cosd(lat)*cosd(spec.lat)*sind((lon-spec.lon)/2)^2
    r=2*6371asin(sqrt(clamp(a,0,1)))/spec.radius_km
    r>=1 ? 0. : (1-r)^4*(1+4r)
end
end
