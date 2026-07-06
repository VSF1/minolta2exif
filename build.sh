#!/bin/bash

echo "Cleaning up old builds..."
rm -rf build/ dist/

echo "Compiling minolta2exif.py for Linux..."
pyinstaller minolta2exif.spec

echo "Build finished. Executable is in the dist/ directory."