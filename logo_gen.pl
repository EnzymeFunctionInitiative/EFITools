#!/usr/bin/env perl

use strict;
use warnings;
use Bio::HMM::Logo;
use FindBin;
use Getopt::Long;

my ($hmmFile, $jsonFile, $pngFile);
my $result = GetOptions(
    "hmm=s"         => \$hmmFile,
    "json=s"        => \$jsonFile,
    "png=s"         => \$pngFile,
);


die "--hmm HMM input argument is required" if not $hmmFile or not -f $hmmFile;
die "--json JSON output argument is required" if not $jsonFile;
die "--png PNG output argument is required" if not $pngFile;


# create the logo object and pass it the path to the hmm file.
my $logo = Bio::HMM::Logo->new({ hmmfile => $hmmFile });


# generate the json string that can be used by the javascript
# code to create an interactive graphic
my $logo_json = $logo->as_json();
open my $json_fh, ">", $jsonFile or die "Unable to write to json file $jsonFile: $!";
print $json_fh $logo_json;
close $json_fh;

# create a static version of the logo and dump it to disk.
my $logo_png = $logo->as_png();

open my $image, ">", $pngFile or die "Unable to write to png file $pngFile: $!";
binmode $image;
print $image $logo_png;
close $image;


