#!/usr/bin/perl -w

#
# dm9toexif.pl
#
# (C) 2008-2010 William Brodie-Tyrrell
# Released under GNU General Public License v3
# 
# Parses DNO*.txt from DM-9 data-back and generates EXIF for scanned jpegs.
#

use Image::ExifTool;

sub Help {
    print "dm9toexif.pl: Converts DNO files to EXIF data in scanned jpegs\n";
    print "(C) 2008-2010 William Brodie-Tyrrell\n\n";
    print "Usage: dm9toexif.pl pattern dno-*.txt\n\n";
    print "jpegs named according to pattern must exist in current directory, with the\n";
    print "following substitutions into the pattern:\n";
    print "\@F becomes frame number\n";
    print "\@U becomes Up-no\n";
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

# expected header contents
@hdr=('Frame', 'Shutter', 'FNo.', 'Lens', '+/-', 'PASM', 'Meter', 'AF', 'Area', 'AFP/RP', 'Drive', 'Flash', 'FL+/-', 'FLMeter', 'ISO', 'Up No.', 'Fix No.', 'yy/mm/dd', 'Time');

# meter modes
%meters=('Multi', 'Multi-segment', 'Ave', 'Center-weighted average', 'Spot', 'Spot', 'OFF', 'Unknown');
# exposure modes
# %exposures=('P', 'Program Exposure', 'A', 'Aperture Priority', 'S', 'Shutter Priority', 'M', 'Manual Exposure');
%exposures=('P','Program AE', 'A', 'Aperture-priority AE', 'S', 'Shutter speed priority AE', 'M', 'Manual');
# AF modes
# %afmodes=('A', 'Automatic Autofocus', 'S', 'Single Shot Autofocus', 'C', 'Continuous Autofocus', 'M', 'Manual Focus');
# AF areas
# %afareas=('[]', 'Wide Focus Area', '-o-', 'Center Local Focus Area', 'o--', 'Left Local Focus Area', '--o', 'Right Local Focus Area', '---', 'Manual Focus');
# release priorities
# %afprp=('AFP', 'AF Priority', 'RP', 'Release Priority', '-', 'Manual Focus');
# flash modes
%flashmodes=('OFF', 'Off', 'ON', 'On', 'RedEye', 'On, Red-eye reduction', 'Rear', 'On', 'WL', 'On');

if($#ARGV >= 0 && $ARGV[0] eq '-h' || $#ARGV < 1){
    Help;
}

$patternarg=shift(@ARGV);

# discover jpegs in the current directory
@jpegs=grep(/.jpg$/i, <*>);

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
    if($hdr =~ /^dno-(\d+)/){
        $hdr=shift(@dno);
    }

    @fields=split("\t", $hdr);
    if(!(@fields eq @hdr)){
	warn "bad header in $dno\n";
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
	    next;
	}

	%exif=();

	# turn values into a hash
	for $i (0 .. $#hdr){
	    $fname=$hdr[ $i ];
	    $value=$fields[ $i ];

	    $exif{ $fname } = $value;
	}

	# build pattern for searching for the matching jpeg,
	# it is assumed to be of the form *upno.jpg
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
	$fname=$matches[0];
	$outfile=$fname;
	$outfile =~ s/\.jpg$/-exif.jpg/i;
	$xmpfile=$fname;
	$xmpfile =~ s/\.jpg/.xmp/i;

	unlink($outfile) if(-e $outfile);
	unlink($xmpfile) if(-e $xmpfile);

	warn "Modifying $fname into $outfile\n";

	my $exifTool = new Image::ExifTool;

	# set EXIF for shutter speed
	$shutter=$exif{'Shutter'};
	if($shutter =~ /^\s*(\d+)\"(\d+)\s*$/){
	    $value=$1+$2/(10^(length($2)));
	    $exifTool->SetNewValue('ShutterSpeedValue', $value);
	    $exifTool->SetNewValue('Exposure Time', $value);
	}
	elsif($shutter =~ /^\s*(\d+)\"\s*$/){
	    $exifTool->SetNewValue('ShutterSpeedValue', $1);
	    $exifTool->SetNewValue('Exposure Time', $1);
	}
	elsif($shutter =~ /^\s*(\d+)\s*$/){
	    $exifTool->SetNewValue('ShutterSpeedValue', 1.0/$1);
	    $exifTool->SetNewValue('Exposure Time', 1.0/$1);
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
	if($exif{'Lens'} =~ /^\s*(\d+)\/(\d+\.?\d*)\s*$/){
	    $focal=$1;
	    $maxap=$2;

	    $exifTool->SetNewValue('FocalLength', $focal);
	    $exifTool->SetNewValue('MaxApertureValue', $maxap);
	}

	# exposure compensation
	$exifTool->SetNewValue('ExposureCompensation', $exif{'+/-'});

	# exposure mode
	$exifTool->SetNewValue('ExposureProgram', $exposures{ $exif{'PASM'} });

	# metering mode
	$exifTool->SetNewValue('MeteringMode', $meters{ $exif{'Meter'} });

	# Flash
	$exifTool->SetNewValue('Flash', $flashmodes{ $exif{'Flash'} });       

	# ISO
	if($exif{'ISO'} =~ /(\d+)/){
	    $exifTool->SetNewValue('ISO', $1);
	}

	# Date/Time
	$datestr=$exif{'yy/mm/dd'} . ':' . $exif{'Time'};
	if($datestr =~ /^(\d\d)\/(\d\d)\/(\d\d):(\d+):(\d+)$/){
	    if($1 < 90){
		$yy=$1+2000;
	    }
	    else{
		$yy=$1+1900;
	    }
	    $datestr="${yy}:${2}:${3} ${4}:{$5}:00";

	    $exifTool->SetNewValue('DateTimeOriginal', $datestr);
	}
	else{
	    warn "Bad date/time format\n";
	}

	# AF mode - ???
	# AF area - ???
	# few tags not sure how to set

	# global assumed settings
	$exifTool->SetNewValue("Make", "Minolta");
	$exifTool->SetNewValue("FileSource", "Film Scanner");
	$exifTool->SetNewValue("Model", "Dynax/Maxxum/Alpha 9");
	
	# write the EXIF to a new jpeg and to an XMP file
	$exifTool->WriteInfo($fname, $outfile);
	$exifTool->WriteInfo(undef, $xmpfile, 'XMP');
    }
}

