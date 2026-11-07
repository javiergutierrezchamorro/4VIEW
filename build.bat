@ECHO OFF
copy /y d:\proyectos\smart.inc\smart.inc .\
D:\FICHEROS\OC\BINNT\ASMC -0 -bin -Fo 4VIEW.COM 4VIEW.ASM
D:\FICHEROS\OC\BINNT\ASMC -3 -bin -Fo 4VIEW386.COM 4VIEW.ASM
D:\FICHEROS\UTIL\UPX --8086 --ultra-brute --no-lzma --overlay=strip 4VIEW.COM
D:\FICHEROS\UTIL\UPX --ultra-brute --no-lzma --overlay=strip 4VIEW386.COM