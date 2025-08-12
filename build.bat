@echo off
setlocal enabledelayedexpansion

echo ====================================
echo GDAL Windows Host Docker Build Script
echo ====================================

echo Checking Docker configuration...
docker info | findstr "OSType: windows" >nul
if %errorlevel% neq 0 (
    echo ERROR: Docker is not configured for Windows containers!
    echo Please switch to Windows containers using Docker Desktop
    echo ^(Right-click Docker Desktop system tray icon ^> "Switch to Windows containers..."^)
    pause
    exit /b 1
)


echo Checking disk space...
for /f "tokens=3" %%i in ('dir /-c "%~dp0" ^| find "bytes free"') do set FREESPACE=%%i
set /a FREESPACE_GB=%FREESPACE:~0,-9%
if %FREESPACE_GB% LSS 10 (
    echo WARNING: Low disk space detected ^(%FREESPACE_GB%GB free^)
    echo Docker build may fail with insufficient space
    echo Please ensure at least 10GB free space
    pause
)

set GDAL_VERSION=3.8.0
set PROJ_VERSION=9.3.0
set GEOS_VERSION=3.12.0
set SQLITE_VERSION=3440000
set DOCKERFILE=docker/Dockerfile.windows-host

set OUTPUT_DIR=windows-host
set BINARIES_DIR=%OUTPUT_DIR%\binaries
set DATA_DIR=%OUTPUT_DIR%\data

echo Creating output directories...
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
if not exist "%BINARIES_DIR%" mkdir "%BINARIES_DIR%"
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
if not exist "%DATA_DIR%\gdal" mkdir "%DATA_DIR%\gdal"
if not exist "%DATA_DIR%\proj" mkdir "%DATA_DIR%\proj"

echo Output directories created:
echo - %OUTPUT_DIR%
echo - %BINARIES_DIR%
echo - %DATA_DIR%

echo.
echo Building GDAL Docker image...
echo Using versions:
echo - GDAL: %GDAL_VERSION%
echo - PROJ: %PROJ_VERSION%
echo - GEOS: %GEOS_VERSION%
echo - SQLite: %SQLITE_VERSION%
echo.


docker build ^
    -f %DOCKERFILE% ^
    --build-arg GDAL_VERSION=%GDAL_VERSION% ^
    --build-arg PROJ_VERSION=%PROJ_VERSION% ^
    --build-arg GEOS_VERSION=%GEOS_VERSION% ^
    --build-arg SQLITE_VERSION=%SQLITE_VERSION% ^
    -t gdal-windows .

if %errorlevel% neq 0 (
    echo.
    echo ==========================================
    echo ERROR: All Docker build attempts failed!
    echo ==========================================
    echo.
    echo This appears to be a Windows Docker container issue.
    echo.  
    echo Troubleshooting steps:
    echo 1. Ensure Docker Desktop is using Windows containers
    echo    ^(Right-click Docker Desktop tray icon ^> "Switch to Windows containers"^)
    echo 2. Restart Docker Desktop completely
    echo 3. Run "docker system prune -a" to clean all Docker data
    echo 4. Check Windows version compatibility with Docker
    echo 5. Ensure Windows Container feature is enabled:
    echo    Enable-WindowsOptionalFeature -Online -FeatureName containers -All
    echo.
    pause
    exit /b 1
)

echo.
echo Docker build completed successfully!
echo.

echo Creating temporary container to extract binaries...
docker create --name gdal-temp gdal-windows

if %errorlevel% neq 0 (
    echo ERROR: Failed to create temporary container!
    pause
    exit /b 1
)

echo Extracting binaries to %BINARIES_DIR%...
docker cp gdal-temp:C:/binaries/. "%BINARIES_DIR%/"

echo Extracting GDAL data to %DATA_DIR%\gdal...
docker cp gdal-temp:C:/gdal-data/. "%DATA_DIR%/gdal/"

echo Extracting PROJ data to %DATA_DIR%\proj...
docker cp gdal-temp:C:/proj-data/. "%DATA_DIR%/proj/"

echo Cleaning up temporary container...
docker rm gdal-temp

if %errorlevel% neq 0 (
    echo WARNING: Failed to remove temporary container gdal-temp
)

echo.
echo ====================================
echo Build and extraction completed!
echo ====================================
echo.
echo Binaries extracted to: %BINARIES_DIR%
echo Data files extracted to: %DATA_DIR%
echo.
echo Available executables:
if exist "%BINARIES_DIR%\gdalinfo.exe" echo - gdalinfo.exe
if exist "%BINARIES_DIR%\ogr2ogr.exe" echo - ogr2ogr.exe  
if exist "%BINARIES_DIR%\ogrinfo.exe" echo - ogrinfo.exe
if exist "%BINARIES_DIR%\gdal_rasterize.exe" echo - gdal_rasterize.exe
if exist "%BINARIES_DIR%\gdal_translate.exe" echo - gdal_translate.exe
echo.


echo Creating environment setup script...
(
echo @echo off
echo echo Setting up GDAL environment...
echo set GDAL_DATA=%cd%\%DATA_DIR%\gdal
echo set PROJ_DATA=%cd%\%DATA_DIR%\proj
echo set PATH=%cd%\%BINARIES_DIR%;%%PATH%%
echo echo GDAL environment configured!
echo echo.
echo echo Available commands:
echo echo - gdalinfo.exe
echo echo - ogr2ogr.exe
echo echo - ogrinfo.exe  
echo echo - gdal_rasterize.exe
echo echo - gdal_translate.exe
echo echo.
echo echo Test with: gdalinfo --version
echo cmd /k
) > "%OUTPUT_DIR%\setup-environment.bat"

echo Environment setup script created: %OUTPUT_DIR%\setup-environment.bat
echo.
echo To use GDAL:
echo 1. Run "%OUTPUT_DIR%\setup-environment.bat" to set up environment
echo 2. Or manually set:
echo    - GDAL_DATA=%cd%\%DATA_DIR%\gdal
echo    - PROJ_DATA=%cd%\%DATA_DIR%\proj
echo    - Add %cd%\%BINARIES_DIR% to PATH
echo.

pause
echo Build process completed successfully!