#!/bin/bash

echo "Cleaning up old builds..."
rm -rf build/ dist/

echo "Installing dependencies..."
pip install -r requirements.txt

echo "Compiling minolta2exif.py for macOS..."
pyinstaller minolta2exif.spec

echo "Build finished. Executable is in the dist/ directory."