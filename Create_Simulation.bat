@echo off
setlocal
cd /d "%~dp0"
set "JULIA_CMD=julia"
where julia >nul 2>nul
if not errorlevel 1 goto found
if exist "%USERPROFILE%\.juliaup\bin\julia.exe" (
    set "JULIA_CMD=%USERPROFILE%\.juliaup\bin\julia.exe"
    goto found
)
echo Khong tim thay Julia. Hay cai Julia 1.13.3 va bat lai file nay.
echo Huong dan: https://julialang.org/downloads/
pause
exit /b 1
:found
"%JULIA_CMD%" --version
echo Dang mo TerraFlux. Lan dau can Internet de cai thu vien va co the mat vai phut.
"%JULIA_CMD%" --threads=2 --project="%~dp0." "%~dp0simulation_setup.jl" --setup
if errorlevel 1 (
    echo.
    echo TerraFlux gap loi. Hay gui lai thong bao loi trong cua so nay.
    pause
    exit /b 1
)
endlocal
