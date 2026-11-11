module TerraFluxProcessControl
export stop_process!
function signal_if_running(process,signal)
    try
        process_exited(process) || kill(process,signal)
    catch
        process_exited(process) || rethrow()
    end
end
"Wait for a cooperative exit, then terminate with a bounded hard-stop fallback."
function stop_process!(process;grace=0.,terminate_grace=2.)
    if !process_exited(process) && timedwait(()->process_exited(process),grace;pollint=0.05)==:timed_out
        signal_if_running(process,Base.SIGTERM)
        if timedwait(()->process_exited(process),terminate_grace;pollint=0.05)==:timed_out
            signal_if_running(process,Base.SIGKILL)
        end
    end
    wait(process)
    nothing
end
end
