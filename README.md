# minolta2exif

These set of scripts are used to add Minolta proprietary data into exif information and update the images.

* dn7toexif.pl is to be used with the output from Minolta DS-100 acessory.
* dm9toexif.pl is to be used with the output from Minolta DM-9 Data Memory Back acessory.

jpegs/tiffs named according to pattern must exist in current directory, with the following substitutions into the pattern:
* @F becomes frame number (from 00 to 99)
* print "\@U becomes Up-no (from 00000 to 99999)
* @R becomes roll number from the DNO-filename (if found)

These scripts also generate .xmp files.
