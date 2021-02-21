#!/usr/bin/perl -w

#
# dm9toexif.pl
#
# (C) 2008-2010 William Brodie-Tyrrell
# Released under GNU General Public License v3
# 
# (C) 2020-2021 Vitor Fonseca
# Released under GNU General Public License v3
#
# http://www.vitorfonseca.com
# 
# Parses DNO*.txt from DM-9 data-back and generates EXIF for scanned jpegs.
#

use Image::ExifTool;
use Image::ExifTool::Minolta;

$script_version = "v2.0";
###################################
# Start of user replaceable values
###################################
$camera_maker =  "Minolta";
$camera_model =	 "Dynax 9";	 # Replace by Dynax 9, Maxxum 9 or Alpha 9 depending on your model
$camera_serial = "00000000"; 	 # Replace by your own serial
$artist_name =   "John Doe";  # Replace by your own name
###################################
# End of user replaceable values
################################### 

sub Help {
	print "$script_version\n";
	print "dm9toexif.pl: Converts DN0 files to EXIF data in scanned jpegs\n";
	print "(C) 2008-2010 William Brodie-Tyrrell\n\n";
	print "(C) 2020-2021 Vitor Fonseca\n\n";
	print "Usage: dm9toexif.pl pattern dn0-*.txt\n\n";
	print "jpegs/tiffs named according to pattern must exist in current directory, with the\n";
	print "following substitutions into the pattern:\n";
	print "\@F becomes frame number (from 00 to 99)\n";
	print "\@U becomes Up-no (from 00000 to 99999)\n";
	print "\@R becomes roll number from the DNO-filename (if found)\n";
	print "Also generates .xmp files\n";
	exit;
}

sub FillPattern {
	my($frame, $upno)=@_;
	my($res);

	$frame=sprintf("%02d", $frame);
	$upno=sprintf("%05d", $upno);

	$res=$pattern;

	$res =~ s/\@F/$frame/ge;
	$res =~ s/\@U/$upno/ge;

	$res;
}

# expected header contents for DM-9
@hdr=('Frame', 'Shutter', 'FNo.', 'Lens', '+/-', 'PASM', 'Meter', 'AF', 'Area', 'AFP/RP', 'Drive', 'Flash', 'FL +/-', 'FLMeter', 'ISO', 'Up No.', 'Fix No.', 'yy/mm/dd', 'Time');
# Header to field name mapping 
@hdr_field=('Frame', 'Shutter', 'FNo.', 'Lens', '+/-', 'PASM', 'Meter', 'AF', 'Area', 'AFP/RP', 'Drive', 'Flash', 'FL', 'FLMeter', 'ISO', 'Up No.', 'Fix No.', 'yy/mm/dd', 'Time');

# meter modes
%meters=('Multi', 'Multi-segment', 'Ave', 'Center-weighted average', 'Spot', 'Spot', 'OFF', 'Unknown');
# exposure modes
# %exposures=('P', 'Program Exposure', 'A', 'Aperture Priority', 'S', 'Shutter Priority', 'M', 'Manual Exposure');
%exposures=('P','Program AE', 'A', 'Aperture-priority AE', 'S', 'Shutter speed priority AE', 'M', 'Manual');
# AF modes
#%afmodes=('A', 'AF-A', 'S', 'AF-S', 'C', 'AF-C', 'M', 'Manual');
# AF areas
#%afareas=('[ ]', 'Wide Focus Area', '-o-', 'Center Local Focus Area', 'o--', 'Left Local Focus Area', '--o', 'Right Local Focus Area', '---', 'Manual Focus');
#%afareamode=('[ ]', 'Wide', '-o-', 'Local', 'o--', 'Local', '--o', 'Local', '---', 'Manual Focus');
#%afpointselected=('[ ]', '(none)', '-o-', 'Center', 'o--', 'Left', '--o', 'Right', '---', '(none)');
# release priorities
#%afprp=('AFP', 'AF Priority', 'RP', 'Release Priority', '-', 'Manual Focus');
# flash modes
#%flashmodes=('OFF', 'Off', 'ON', 'On', 'RedEye', 'On, Red-eye reduction', 'Rear', 'On', 'WL', 'On');

if($#ARGV >= 0 && $ARGV[0] eq '-h' || $#ARGV < 1){
	Help;
}

$patternarg=shift(@ARGV);

# discover jpegs in the current directory
@jpegs=(<*.jpg>, <*.tif>);

# iterate over all the given DNO files
for $dno (@ARGV){
	
	open(DNO, $dno) || die "Can't open $dno: $!\n";
	@dno=<DNO>;
	close(DNO);

	warn "Processing $dno\n";

	# pre-fill pattern with roll-number
	$pattern=$patternarg;
	if($pattern =~ /\@R/){
		if($dno =~ /(\d+)/){
			$roll=$1;
			$pattern =~ s/\@R/$roll/ge;
		}
		else{
			warn "Roll number (\@R) specified in filename pattern but not parseable from $dno\n";
		}
	}

	# check the file header
	$hdr=shift(@dno);
	if($hdr =~ /^dn(\d+)-(\d+),ISO:(\d+)/){
		$iso= $3;
		$hdr=shift(@dno);
		warn "\nISO found $iso\n";
	} else {
		$hdr=shift(@dno);
	}

	@fields=split("\t", $hdr);
	@fields=trim(@fields);
	if(!(@fields eq @hdr)){
		warn "bad header in $dno \n Fields @fields \n Header @hdr\n";
		next;
	}

	# process all the frames listed in the file
	for $frame (@dno){
		$frame =~ s/^\s+//;
		$frame =~ s/\s+$//;
		next if(length($frame) == 0);

		@fields=split("\t", $frame);

		if($#fields != $#hdr){
			warn "bad frame line, wrong field count\n";
			warn "$#fields - $#hdr -> $hdr\n";
			next;
		}

		%exif=();

		# turn values into a hash
		for $i (0 .. $#hdr){
			$fname=$hdr_field[ $i ];
			$value=$fields[ $i ];
			$exif{ $fname } = $value;
		}

		# build pattern for searching for the matching jpeg,
		# it is assumed to be of the form *upno.jpg
		# $fpat='^.*('. $exif{'Up No.'} . ')\.jpg$';
		$fpat=FillPattern($exif{'Frame'}, $exif{'Up No.'});

		@matches=grep(/$fpat/, @jpegs);

		if($#matches < $[){
			warn "No match for ". $exif{'Up No.'} . ", skipping line\n";
			next;
		}
		if($#matches > $[){
			warn "Multiple matches for ". $exif{'Up No.'} . ", skipping line\n";
		}

		# decide on filenames
		$fname = $matches[0];
		$outfile = $fname;
		$outfile =~ s/\.jpg$/-exif.jpg/;
		$outfile =~ s/\.JPG$/-exif.JPG/;
		$outfile =~ s/\.tif$/-exif.tif/;
		$outfile =~ s/\.TIF$/-exif.TIF/;
		$xmpfile=$fname;
		$xmpfile =~ s/\.jpg/.xmp/;
		$xmpfile =~ s/\.JPG/.xmp/;
		$xmpfile =~ s/\.tif/.xmp/;
		$xmpfile =~ s/\.TIF/.xmp/;

		unlink($outfile) if(-e $outfile);
		unlink($xmpfile) if(-e $xmpfile);

		warn "Modifying $fname into $outfile\n";

		my $exifTool = new Image::ExifTool;

		# set EXIF for shutter speed
		$shutter=$exif{'Shutter'};
		if($shutter =~ /^\s*(\d+)\"(\d+)\s*$/){
			$value=$1+$2/(10^(length($2)));
			$exifTool->SetNewValue('ShutterSpeedValue', $value);
			$exifTool->SetNewValue('ExposureTime', $value);
		}
		elsif($shutter =~ /^\s*(\d+)\"\s*$/){
			$exifTool->SetNewValue('ShutterSpeedValue', $1);
			$exifTool->SetNewValue('ExposureTime', $1);
		}
		elsif($shutter =~ /^\s*(\d+)\s*$/){
			$exifTool->SetNewValue('ShutterSpeedValue', 1.0/$1);
			$exifTool->SetNewValue('ExposureTime', 1.0/$1);
		}
		elsif($shutter =~ /Bulb/i){
			;
		}
		else{
			warn "Bad shutter value '$shutter'\n";
			next;
		}

		# f-number
		if($exif{'FNo.'} =~ /(\d+\.?\d*)/){
			$exifTool->SetNewValue('FNumber', $1);
		}

		# focal length / max aperture
		if($exif{'Lens'} =~ /^\s*(\d+)\ \ \/(\d+\.?\d*)\s*$/){
			$focal=$1;
			$maxap=$2;

			$exifTool->SetNewValue('FocalLength', $focal);
			$exifTool->SetNewValue('FocalLengthIn35mmFormat', $focal);
			$exifTool->SetNewValue('MaxApertureValue', $maxap);
		} else { 
			if($exif{'Lens'} =~ /^\s*(\d+)\ \/(\d+\.?\d*)\s*$/){
				$focal=$1;
				$maxap=$2;

				$exifTool->SetNewValue('FocalLength', $focal);
				$exifTool->SetNewValue('FocalLengthIn35mmFormat', $focal);
				$exifTool->SetNewValue('MaxApertureValue', $maxap);
			} else {
				if($exif{'Lens'} =~ /^\s*(\d+)\/(\d+\.?\d*)\s*$/){
					$focal=$1;
					$maxap=$2;

					$exifTool->SetNewValue('FocalLength', $focal);
					$exifTool->SetNewValue('FocalLengthIn35mmFormat', $focal);
					$exifTool->SetNewValue('MaxApertureValue', $maxap);
				} else {
					warn "Bad lens format\n";
				}
			}
		}
		$exifTool->SetNewValue('ImageNumber', $exif{'Frame'});

		# exposure compensation
		$exifTool->SetNewValue('ExposureCompensation', trim($exif{'+/-'}));

		# exposure mode
		$exifTool->SetNewValue('ExposureProgram', $exposures{ trim($exif{'PASM'}) });

		# metering mode
		$exifTool->SetNewValue('MeteringMode', $meters{ trim($exif{'Meter'}) });

		# Flash
		if($exif{'FL'} =~ /(\d+\.\d)/) {
			$exifTool->SetNewValue('Flash', 'Fired'); # Fired
			$exifTool->SetNewValue('Minolta:FlashExposureComp', ${1});
		} else {
			$exifTool->SetNewValue('Flash', 'No Flash'); # No Flash
		}
		# ISO
		$exifTool->SetNewValue('ISO', trim($exif{'ISO'}));

		# Date/Time
		$datestr=$exif{'yy/mm/dd'} . ':' . $exif{'Time'};
		#warn "date/time $datestr\n";
		if($datestr =~ /^(\d\d)\/(\d\d)\/(\d\d):(\d+):(\d+)$/){
			$datestr="20${1}:${2}:${3} ${4}:${5}:00";

			#warn "date/time $datestr\n";
			$exifTool->SetNewValue('DateTimeOriginal', $datestr);
		}
		else{
			warn "Bad date/time format\n";
		}

		# AF mode 
		#$exifTool->SetNewValue("DriveMode", $afmodes{trim($exif{'AF'})});
		#$exifTool->SetNewValue("Minolta:FocusMode", $afmodes{trim($exif{'AF'})});
		# AF area - ???
		#$exifTool->SetNewValue("AFAreaMode", $afareamode{trim($exif{'Area'})});
		#$exifTool->SetNewValue("Minolta:AFPoints", $afpointselected{trim($exif{'Area'})});
		# few tags not sure how to set

		# global assumed settings
		$exifTool->SetNewValue("Make", trim($camera_maker));
		$exifTool->SetNewValue("FileSource", "Film Scanner");
		$exifTool->SetNewValue("Model", trim($camera_model));
		$exifTool->SetNewValue("CameraSerialNumber", trim($camera_serial)); 	
		$exifTool->SetNewValue("SerialNumber", trim($camera_serial)); 	
		$exifTool->SetNewValue("Artist", trim($artist_name)); 
		$exifTool->SetNewValue("Copyright", trim($artist_name) . ", All rights reserved");	 


		# write the EXIF to a new jpeg and to an XMP file
		$exifTool->WriteInfo($fname, $outfile);
		$exifTool->WriteInfo(undef, $xmpfile, 'XMP');
	}
}

sub trim 
{
	my @out = @_;
	for (@out) 
	{
		s/^\s+//;
		s/\s+$//;
	}
	return wantarray ? @out : $out[0];
}
