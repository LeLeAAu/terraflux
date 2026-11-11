module TerraFluxThermalPatch
export thermal_spec, patch_weight
function thermal_spec(;lon,lat,radius_km,layer,delta_k)
    all(x->x isa Real && !(x isa Bool) && isfinite(x) && isfinite(Float64(x)),(lon,lat,radius_km,delta_k)) || error("Thông số vùng nhiệt phải hữu hạn.")
    lon,lat,radius_km,delta_k=Float64.((lon,lat,radius_km,delta_k))
    -180<=lon<=180 && -90<=lat<=90 || error("Tọa độ ngoài phạm vi.")
    0<radius_km<=pi*6371 || error("Bán kính phải >0 và không vượt nửa chu vi Trái Đất (πR).")
    layer isa Integer && !(layer isa Bool) && 1<=layer<=typemax(Int) || error("Tầng phải là số nguyên dương có trong mô hình.")
    delta_k!=0 || error("ΔT phải khác 0; trạng thái sau tác động phải có T > 0 K.")
    (;lon=Float64(lon),lat=Float64(lat),radius_km=Float64(radius_km),layer=Int(layer),delta_k=Float64(delta_k))
end
function patch_weight(lon,lat,spec)
    a=sind((lat-spec.lat)/2)^2+cosd(lat)*cosd(spec.lat)*sind((lon-spec.lon)/2)^2
    r=2*6371asin(sqrt(clamp(a,0,1)))/spec.radius_km
    r>=1 ? 0. : (1-r)^4*(1+4r)
end
end
