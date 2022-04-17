#!/usr/bin/perl -w

#
# dn7toexif.pl
#
# (C) 2008-2010 William Brodie-Tyrrell
# Released under GNU General Public License v3
# 
# (C) 2020-2021 Vitor Fonseca
# Released under GNU General Public License v3
# http://www.vitorfonseca.com
# 
# Parses DN0*.txt from DS-100 data saver and generates EXIF for scanned jpegs.
#

use Image::ExifTool;
use Image::ExifTool::Minolta;

$script_version = "v2.1";
###################################
# Start of user replaceable values
################################### 
$camera_maker =  "Minolta";
$camera_model =	"Dynax 7";	 	 # Replace by Dynax 7, Maxxum 7 or Alpha 7 depending on your model
$camera_serial = "00000000"; 	 # Replace by your own serial
$artist_name = "John Doe";  # Replace by your own name
###################################
# End of user replaceable values
################################### 

sub Help {
	print "$script_version\n";
	print "dn7toexif.pl: Converts DN0 files to EXIF data in scanned jpegs\n";
	print "(C) 2008-2010 William Brodie-Tyrrell\n\n";
	print "(C) 2020-2022 Vitor Fonseca\n\n";
	print "Usage: dn7toexif.pl pattern dn0-*.txt\n\n";
	print "jpegs/tiffs named according to pattern must exist in current directory, with the\n";
	print "following substitutions into the pattern:\n";
	print "\@F becomes frame number (from 00 to 99)\n";
	print "\@U becomes Up-no (from 00000 to 99999)\n";
	print "\@R becomes roll number from the DNO-filename (if found)\n";
	print "Also generates .xmp files\n";
	exit;
}

sub FillPattern {
	my($frame)=@_;
	my($res);

	$frame=sprintf("%02d", $frame);

	$res=$pattern;

	$res =~ s/\@F/$frame/ge;

	$res;
}

# expected header contents
@hdr=('Frame', 'Shutter', 'FNo.', 'Lens', '+/-', 'PASM', 'Meter', 'FL +/-', 'yy/mm/dd', 'Time');
@hdr_field=('Frame', 'Shutter', 'FNo.', 'Lens', '+/-', 'PASM', 'Meter', 'FL', 'yy/mm/dd', 'Time');

# meter modes (Meter field)
%meters=('Multi', 'Multi-segment', 'Ave', 'Center-weighted average', 'Spot', 'Spot', 'OFF', 'Unknown');

# exposure modes (PASM field)
%exposures=('P','Program AE', 'A', 'Aperture-priority AE', 'S', 'Shutter speed priority AE', 'M', 'Manual');

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
		# it is assumed to be of the form pattern-*.jpg
		$fpat=FillPattern($exif{'Frame'});

		@matches=grep(/$fpat/, @jpegs);

		if($#matches < $[){
			warn "No match for, skipping frame number ". $exif{'Frame'} ."\n";
			next;
		}
		if($#matches > $[){
			warn "Multiple matches for ". $matches[0] . ", skipping frame ". $exif{'Frame'} ."\n";
		}

		# decide on filenames
		$fname = $matches[0];
		$outfile = $fname;
		$outfile =~ s/\.jpg$/-exif.jpg/;
		$outfile =~ s/\.JPG$/-exif.JPG/;
		$outfile =~ s/\.tif$/-exif.tif/;
		$outfile =~ s/\.TIF$/-exif.TIF/;
		$outfile =~ s/\.dng$/-exif.dng/;
		$outfile =~ s/\.DNG$/-exif.DNG/;
		$xmpfile=$fname;
		$xmpfile =~ s/\.jpg/.xmp/;
		$xmpfile =~ s/\.JPG/.xmp/;
		$xmpfile =~ s/\.tif/.xmp/;
		$xmpfile =~ s/\.TIF/.xmp/;
		$xmpfile =~ s/\.dng/.xmp/;
		$xmpfile =~ s/\.DNG/.xmp/;

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
		} elsif($shutter =~ /^\s*(\d+)\"\s*$/){
			$exifTool->SetNewValue('ShutterSpeedValue', $1);
			$exifTool->SetNewValue('ExposureTime', $1);
		} elsif($shutter =~ /^\s*(\d+)\s*$/){
			$exifTool->SetNewValue('ShutterSpeedValue', 1.0/$1);
			$exifTool->SetNewValue('ExposureTime', 1.0/$1);
		} elsif($shutter =~ /Bulb/i){
			# empty on purpose
		} else {
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
		} elsif($exif{'Lens'} =~ /^\s*(\d+)\ \/(\d+\.?\d*)\s*$/){
			$focal=$1;
			$maxap=$2;

			$exifTool->SetNewValue('FocalLength', $focal);
			$exifTool->SetNewValue('FocalLengthIn35mmFormat', $focal);
			$exifTool->SetNewValue('MaxApertureValue', $maxap);
		} elsif($exif{'Lens'} =~ /^\s*(\d+)\/(\d+\.?\d*)\s*$/){
			$focal=$1;
			$maxap=$2;

			$exifTool->SetNewValue('FocalLength', $focal);
			$exifTool->SetNewValue('FocalLengthIn35mmFormat', $focal);
			$exifTool->SetNewValue('MaxApertureValue', $maxap);
		} else {
			warn "Bad lens format\n";
		}

		# image number
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
		$exifTool->SetNewValue('ISO', trim($iso));

		# Date/Time
		$datestr=$exif{'yy/mm/dd'} . ':' . $exif{'Time'};
		# warn "date/time $datestr\n";
		if($datestr =~ /^(\d\d\d\d)\/(\d\d)\/(\d\d):(\d+):(\d+)$/){
			$datestr="${1}:${2}:${3} ${4}:${5}:00";

			#warn "date/time $datestr\n";
			$exifTool->SetNewValue('DateTimeOriginal', $datestr);
		} else {
			warn "Bad date/time format\n";
		}

		# AF mode - ???
		# AF area - ???
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
