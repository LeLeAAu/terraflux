module TerraFluxLocalOpen
export local_open_command, open_local_path
function local_open_command(path;platform=Sys.iswindows() ? :windows : Sys.isapple() ? :macos : :linux)
    target=abspath(path)
    ispath(target) || error("Không tìm thấy: $target")
    # Pass paths directly as arguments. cmd /c would interpret %, & and other shell syntax.
    platform==:windows && return isdir(target) ? `explorer.exe $target` : `notepad.exe $target`
    platform==:macos && return `open $target`
    platform==:linux && return `xdg-open $target`
    error("Nền tảng mở tệp không hỗ trợ: $platform")
end
open_local_path(path)=run(local_open_command(path);wait=false)
end
