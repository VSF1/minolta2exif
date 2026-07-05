@ECHO OFF

ECHO Cleaning up old builds...
IF EXIST build ( RMDIR /S /Q build )
IF EXIST dist ( RMDIR /S /Q dist )

ECHO Installing dependencies...
pip install -r requirements.txt

ECHO Compiling minolta2exif.py for Windows...
pyinstaller minolta2exif.spec