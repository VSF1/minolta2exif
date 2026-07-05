#!/usr/bin/env python3
#
# minolta_exif_lib.py
#
# (C) 2026 Vitor Fonseca
# Released under GNU General Public License v3
# http://www.vitorfonseca.com
#
# This script contains the core logic for parsing Minolta DNO files
# and generating EXIF data.
#

import os
import re
import exiftool

METERS = {
    'Multi': 'Multi-segment', 'Ave': 'Center-weighted average',
    'Spot': 'Spot', 'OFF': 'Unknown'
}
EXPOSURES = {
    'P': 'Program AE', 'A': 'Aperture-priority AE',
    'S': 'Shutter speed priority AE', 'M': 'Manual'
}

def process_dno_file(dno_file, pattern_arg, all_images, settings, logger):
    """Processes a single DNO file and applies EXIF data to matching images."""
    logger.write(f"Processing {dno_file}\n")
    try:
        with open(dno_file, 'r') as f:
            lines = [line.strip() for line in f.readlines()]
    except IOError as e:
        logger.write(f"Error: Can't open {dno_file}: {e}\n")
        return

    pattern = pattern_arg
    roll_match = re.search(r'-0*(\d+)', os.path.basename(dno_file))
    if '@R' in pattern:
        if roll_match:
            pattern = pattern.replace('@R', roll_match.group(1))
        else:
            logger.write(f"Warning: Roll number (@R) in pattern but not found in {dno_file}\n")

    iso = None
    if lines and re.match(r'^dn\d+-\d+,ISO:\d+', lines[0]):
        iso_match = re.match(r'^dn\d+-\d+,ISO:(\d+)', lines[0])
        if iso_match:
            iso = iso_match.group(1)
            logger.write(f"\nISO found {iso}\n\n")
        lines.pop(0)

    if not lines:
        logger.write(f"Warning: {dno_file} is empty or contains no data.\n")
        return

    header_line = lines.pop(0)
    header_fields = [h.strip() for h in header_line.split('\t')]

    for line in lines:
        if not line: continue
        fields = [f.strip() for f in line.split('\t')]
        if len(fields) != len(header_fields):
            logger.write(f"Warning: Bad frame line, wrong field count. Skipping.\n")
            continue

        exif_data = dict(zip(header_fields, fields))
        frame_no = exif_data.get('Frame')
        up_no = exif_data.get('Up No.')

        fpat = pattern.replace('@F', f"{int(frame_no):02d}")
        if up_no is not None and '@U' in fpat:
            fpat = fpat.replace('@U', f"{int(up_no):05d}")

        matches = [img for img in all_images if re.search(fpat, img, re.IGNORECASE)]

        if not matches:
            logger.write(f"Warning: No match for pattern '{fpat}', skipping frame {frame_no}\n")
            continue
        if len(matches) > 1:
            logger.write(f"Warning: Multiple matches for pattern '{fpat}', skipping frame {frame_no}\n")
            continue

        image_filename = matches[0]
        base, ext = os.path.splitext(image_filename)
        outfile = f"{base}-exif{ext}"
        xmpfile = f"{base}.xmp"

        logger.write(f"Modifying {image_filename} into {outfile}\n")

        params = {}
        shutter = exif_data.get('Shutter', '')
        if '"' in shutter:
            parts = shutter.replace('"', ' ').split()
            try:
                value = float(parts[0]) + float(f"0.{parts[1]}")
                params['EXIF:ShutterSpeedValue'] = value; params['EXIF:ExposureTime'] = value
            except (ValueError, IndexError): logger.write(f"Warning: Bad shutter value '{shutter}'\n")
        elif shutter.isdigit():
            params['EXIF:ShutterSpeedValue'] = 1.0 / int(shutter); params['EXIF:ExposureTime'] = 1.0 / int(shutter)
        
        if fno := exif_data.get('FNo.', ''): params['EXIF:FNumber'] = fno
        if lens := exif_data.get('Lens', ''):
            if m := re.search(r'^\s*(\d+)\s*/\s*(\d+\.?\d*)\s*$', lens):
                params['EXIF:FocalLength'] = int(m.group(1)); params['EXIF:FocalLengthIn35mmFormat'] = int(m.group(1)); params['EXIF:MaxApertureValue'] = float(m.group(2))
            else: logger.write(f"Warning: Bad lens format '{lens}'\n")
        
        params['EXIF:ImageNumber'] = frame_no
        if comp := exif_data.get('+/-'): params['EXIF:ExposureCompensation'] = comp
        if pasm := exif_data.get('PASM'): params['EXIF:ExposureProgram'] = EXPOSURES.get(pasm)
        if meter := exif_data.get('Meter'): params['EXIF:MeteringMode'] = METERS.get(meter)
        if fl_match := re.search(r'(\d+\.\d)', exif_data.get('FL', '')):
            params['EXIF:Flash'] = 'Fired'; params['MakerNotes:FlashExposureComp'] = fl_match.group(1)
        else: params['EXIF:Flash'] = 'No Flash'
        
        if frame_iso := exif_data.get('ISO'): params['EXIF:ISO'] = frame_iso
        elif iso: params['EXIF:ISO'] = iso

        date, time = exif_data.get('yy/mm/dd', ''), exif_data.get('Time', '')
        if date and time:
            if len(date.split('/')[0]) == 4: # yyyy/mm/dd
                if (d_m := re.match(r'(\d{4})/(\d{2})/(\d{2})', date)) and (t_m := re.match(r'(\d+):(\d+)', time)):
                    params['EXIF:DateTimeOriginal'] = f"{d_m.group(1)}:{d_m.group(2)}:{d_m.group(3)} {int(t_m.group(1)):02d}:{int(t_m.group(2)):02d}:00"
            else: # yy/mm/dd
                if (d_m := re.match(r'(\d{2})/(\d{2})/(\d{2})', date)) and (t_m := re.match(r'(\d+):(\d+)', time)):
                    params['EXIF:DateTimeOriginal'] = f"20{d_m.group(1)}:{d_m.group(2)}:{d_m.group(3)} {int(t_m.group(1)):02d}:{int(t_m.group(2)):02d}:00"

        params.update({
            "EXIF:Make": settings.get("CAMERA_MAKER"), "EXIF:FileSource": "Film Scanner",
            "EXIF:Model": settings.get("CAMERA_MODEL"), "EXIF:CameraSerialNumber": settings.get("CAMERA_SERIAL"),
            "EXIF:SerialNumber": settings.get("CAMERA_SERIAL"), "EXIF:Artist": settings.get("ARTIST_NAME"),
            "EXIF:Copyright": f'{settings.get("ARTIST_NAME")}, All rights reserved'
        })

        try:
            with exiftool.ExifTool() as et:
                et.execute_json("-o", outfile, *[f"-{k}={v}" for k, v in params.items() if v is not None], image_filename)
                et.execute_json("-o", xmpfile, "-tagsfromfile", "@", "-all:all", *[f"-{k}={v}" for k, v in params.items() if v is not None], "-ext", "xmp")
        except Exception as e:
            logger.write(f"Error writing EXIF for {image_filename}: {e}\n")