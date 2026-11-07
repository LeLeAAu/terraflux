module TerraFluxModelProgress
using Dates, SpeedyWeather
export ModelProgress, report_progress!

"Read the model clock after completed steps; never advance or modify it."
mutable struct ModelProgress{F} <: SpeedyWeather.AbstractCallback
    start::DateTime
    finish::DateTime
    report::F
    next_percent::Int
    wall_start::UInt64
end
ModelProgress(start,finish,report)=ModelProgress(start,finish,report,0,time_ns())

function report_progress!(p::ModelProgress,now;phase="integrating",force=false)
    total=Dates.value(p.finish-p.start)/3_600_000
    done=clamp(Dates.value(now-p.start)/3_600_000,0,total)
    percent=clamp(floor(Int,100done/total),0,100)
    !force && percent<p.next_percent && return
    elapsed=(time_ns()-p.wall_start)/1e9
    eta=done>0 ? max(0,round(Int,elapsed*(total-done)/done)) : -1
    p.report((;phase,percent,hours_done=done,hours_total=total,model_time=string(now),eta_seconds=eta))
    p.next_percent=5*(percent÷5+1)
    nothing
end
function SpeedyWeather.initialize!(p::ModelProgress,vars,model)
    p.wall_start=time_ns();p.next_percent=0
    report_progress!(p,vars.prognostic.clock.time;force=true)
end
SpeedyWeather.callback!(p::ModelProgress,vars,model)=report_progress!(p,vars.prognostic.clock.time)
# Finalizing callbacks does not certify output or force an incomplete clock to 100%.
SpeedyWeather.finalize!(::ModelProgress,vars,model)=nothing
end
