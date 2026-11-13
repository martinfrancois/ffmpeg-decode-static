@echo off
rem Runs one script of this repository in MSYS2 bash with the 64-bit MSVC
rem compiler set up. The scripts are bash, FFmpeg's build needs a POSIX shell
rem with make, and MSVC needs the environment that vcvarsall.bat prepares.
rem
rem Usage: scripts\msvc-env.cmd <script in scripts\> [arguments]
rem   e.g. scripts\msvc-env.cmd build.sh x86_64-pc-windows-msvc
rem The arguments become part of a bash command line: write paths with forward
rem slashes, and use no spaces, quotes or other characters the shell reads.
rem
rem Needs Visual Studio with the C++ tools, and MSYS2 with the packages make,
rem diffutils, nasm and pkgconf. build.sh also needs Python 3 on PATH.
rem MSYS2_ROOT says where MSYS2 is installed (default: C:\msys64).
setlocal

if "%~1"=="" (
    echo usage: scripts\msvc-env.cmd ^<script^> [arguments] 1>&2
    exit /b 2
)

if not defined MSYS2_ROOT set "MSYS2_ROOT=C:\msys64"
if not exist "%MSYS2_ROOT%\usr\bin\bash.exe" (
    echo error: MSYS2 not found in %MSYS2_ROOT% 1>&2
    exit /b 1
)

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VSINSTALL="
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%i"
if not defined VSINSTALL (
    echo error: no Visual Studio installation with the C++ tools found 1>&2
    exit /b 1
)
call "%VSINSTALL%\VC\Auxiliary\Build\vcvarsall.bat" x64 || exit /b 1

rem Hands the MSVC environment to bash and keeps bash in this directory.
set MSYSTEM=MSYS
set MSYS2_PATH_TYPE=inherit
set CHERE_INVOKING=1
cd /d "%~dp0.."
"%MSYS2_ROOT%\usr\bin\bash.exe" -lc "scripts/%*"
exit /b %ERRORLEVEL%
