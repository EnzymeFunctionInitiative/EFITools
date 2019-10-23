#!/usr/bin/env perl

use strict;
use warnings;
#use Bio::HMM::Logo;
use File::Basename;
use FindBin;
use Getopt::Long;

use lib dirname(__FILE__) . "/../lib";
use EFI::HMM::Logo;


my ($hmmFile, $jsonFile, $pngFile);
my $result = GetOptions(
    "hmm=s"         => \$hmmFile,
    "json=s"        => \$jsonFile,
    "png=s"         => \$pngFile,
);


die "--hmm HMM input argument is required" if not $hmmFile or not -f $hmmFile;
die "--json JSON output argument is required" if not $jsonFile;
die "--png PNG output argument is required" if not $pngFile;

my $makeLogo = init_logo();

die "Unable to initialize logo code" if not $makeLogo;

make_logo($hmmFile, $jsonFile, $pngFile);


