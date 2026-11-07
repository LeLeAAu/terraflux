@echo off
setlocal
cd /d "%~dp0"
set "LOG_FILE=%~dp0simulation_setup.log"
echo ======================================================== >> "%LOG_FILE%" 2>&1
echo [Create_Simulation] Khoi dong luc %DATE% %TIME% >> "%LOG_FILE%" 2>&1
set "JULIA_CMD=julia"
where julia >nul 2>nul
if not errorlevel 1 goto found
if exist "%USERPROFILE%\.juliaup\bin\julia.exe" (
    set "JULIA_CMD=%USERPROFILE%\.juliaup\bin\julia.exe"
    goto found
)
echo Khong tim thay Julia. Hay cai Julia 1.13.3 va bat lai file nay.
echo Huong dan: https://julialang.org/downloads/
echo [ERROR] Khong tim thay Julia trong PATH hoac %%USERPROFILE%%\.juliaup\bin\julia.exe >> "%LOG_FILE%" 2>&1
pause
exit /b 1
:found
echo Julia runtime: %JULIA_CMD% >> "%LOG_FILE%" 2>&1
"%JULIA_CMD%" --version >> "%LOG_FILE%" 2>&1
"%JULIA_CMD%" --version
echo Dang mo TerraFlux. Lan dau can Internet de cai thu vien va co the mat vai phut.
"%JULIA_CMD%" --threads=2 --project="%~dp0." "%~dp0simulation_setup.jl" --setup
if errorlevel 1 (
    echo.
    echo [ERROR] TerraFlux Create_Simulation thoat voi ma loi %ERRORLEVEL% >> "%LOG_FILE%" 2>&1
    echo TerraFlux gap loi. Hay xem chi tiet trong file: simulation_setup.log
    echo Hoac gui lai thong bao loi trong cua so nay.
    pause
    exit /b 1
)
echo [Create_Simulation] Ket thuc binh thuong. >> "%LOG_FILE%" 2>&1
endlocal
