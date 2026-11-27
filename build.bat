@ECHO OFF
rem 4VIEW build: 4VIEW.COM (8086) and 4VIEW386.COM (386+), both UPX-packed.
copy /y d:\proyectos\smart.inc\smart.inc .\

rem SMARTPP listings for inspection only (they are not assembled).
..\SMART.INC\SMARTPP -m86 -v -mark -o 4VIEW86.SMART.ASM 4VIEW.ASM
..\SMART.INC\SMARTPP -m386 -v -mark -o 4VIEW386.SMART.ASM 4VIEW.ASM

rem Stop at the first assembler error: do not pack a stale COM.
D:\FICHEROS\OC\BINNT\ASMC -0 -bin -Fo 4VIEW.COM 4VIEW.ASM
if errorlevel 1 goto fail
D:\FICHEROS\OC\BINNT\ASMC -3 -bin -Fo 4VIEW386.COM 4VIEW.ASM
if errorlevel 1 goto fail

D:\FICHEROS\UTIL\UPX --8086 --ultra-brute --no-lzma --overlay=strip 4VIEW.COM
D:\FICHEROS\UTIL\UPX --ultra-brute --no-lzma --overlay=strip 4VIEW386.COM
goto end

:fail
echo.
echo BUILD FAILED - see the ASMC messages above.
exit /b 1

:end
