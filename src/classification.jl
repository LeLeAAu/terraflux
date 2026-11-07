module TerraFluxClassification
export classify_system, US_KINDS, US_BASINS, US_TROPICAL_BOUNDS

# Sources, definitions and rounding policy: ../STORM_CLASSIFICATION_US.txt.
const US_TROPICAL_BOUNDS = (34,64,83,96,113,137)
const US_KINDS = ("low","disturbance","tropical","subtropical","extratropical","posttropical","remnant")
const US_BASINS = (:wpac,:atlantic,:epac,:cpac,:other,:unspecified)

"""
Classify a DECLARED system nature, using US 1-minute / 10-m wind thresholds.
Nature is supplied by a validated source/scenario, never inferred from wind or MSLP.
Unknown/nonstandard wind basis leaves tropical intensity unclassified. `basin` is
source metadata, independent of the camera. SSHWS outside hurricane basins is an
explicit wind-equivalent display, not an official local category.
"""
function classify_system(kind,wind;basin=:unspecified,wind_average_minutes=nothing,wind_height_m=nothing)
    kind in (US_KINDS...,"model_low","model_warm","model_cold") || throw(ArgumentError("Loại hệ thống không hỗ trợ: $kind"))
    basin in US_BASINS || throw(ArgumentError("Lưu vực không hỗ trợ: $basin"))
    isfinite(wind) && wind>=0 || throw(ArgumentError("Gió phải hữu hạn, không âm."))
    result(category,code,label;sshws=nothing,equivalent=false,major_hurricane=false,super_typhoon=false,reason="") =
        (;nature=String(kind),basin,category,code,label,sshws,equivalent,major_hurricane,super_typhoon,reason)
    kind=="model_low" && return result(:MODEL_LOW,"L?","Ứng viên xoáy mô hình";
        reason="Chưa xác nhận cấu trúc nhiệt đới; gió tầng mô hình không phải gió duy trì 1 phút ở 10 m.")
    kind=="model_warm" && return result(:MODEL_WARM,"W","Dấu hiệu lõi ấm";
        reason="Dị thường nhiệt hai dải sigma; chưa xác nhận tropical cyclone hay gió chuẩn SSHWS.")
    kind=="model_cold" && return result(:MODEL_COLD,"C","Dấu hiệu lõi lạnh";
        reason="Dị thường nhiệt hai dải sigma; chưa xác nhận front hay nguồn năng lượng ngoại nhiệt đới.")
    kind=="low" && return result(:LOW,"LOW","Vùng áp thấp";reason="Chưa khai báo cấu trúc xoáy thuận nhiệt đới.")
    kind=="disturbance" && return result(:L,"DB","Nhiễu động nhiệt đới")
    kind=="extratropical" && return result(:EX,"EX","Xoáy thuận ngoại nhiệt đới")
    kind=="posttropical" && return result(:POST,"PT","Xoáy thuận hậu nhiệt đới")
    if !(wind_average_minutes==1 && wind_height_m==10)
        return result(:UNKNOWN,"?","Chưa xếp cường độ";
            reason="Cần gió cực đại duy trì 1 phút ở 10 m; không tự quy đổi gió giật, gió 10 phút hoặc gió tầng sigma.")
    end
    if kind=="remnant"
        wind<34 || throw(ArgumentError("Remnant low phải có gió dưới 34 knot; kiểm tra lại loại hệ thống."))
        return result(:RL,"RL","Áp thấp tàn dư")
    elseif kind=="subtropical"
        return wind<34 ? result(:SD,"SD","Áp thấp cận nhiệt đới") : result(:SS,"SS","Bão cận nhiệt đới")
    end
    wind<34 && return result(:D,"TD","Áp thấp nhiệt đới")
    wind<64 && return result(:S,"TS","Bão nhiệt đới")
    category=count(b->wind>=b,US_TROPICAL_BOUNDS)-1
    glyph=Symbol("C",category)
    if basin==:wpac
        super=wind>=130
        return result(glyph,super ? "STY" : "TY",super ? "Super typhoon" : "Typhoon";
            sshws=category,equivalent=true,super_typhoon=super)
    elseif basin in (:atlantic,:epac,:cpac)
        major=category>=3
        return result(glyph,major ? "MH" : "HU",major ? "Major hurricane" : "Hurricane";
            sshws=category,major_hurricane=major)
    end
    result(glyph,"TC","Xoáy thuận nhiệt đới";sshws=category,equivalent=true)
end
end
