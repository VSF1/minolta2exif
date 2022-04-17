@ECHO OFF

REM Command to install compiler
REM perl -MCPAN -e "install PAR::Packer"

ECHO compiling dm9toexif
pp -o bin/dm9toexif.exe dm9toexif.pl | tee -a log/dm9toexif.log 2>&1
ECHO compiling dn7toexif
pp -o bin/dn7toexif.exe dn7toexif.pl | tee -a log/dn7toexif.log 2>&1