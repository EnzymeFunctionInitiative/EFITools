#!/bin/env perl

use strict;
use warnings;

use FindBin;

use lib "$FindBin::Bin/../lib";

use EFI::LengthHistogram;


my $histo = new EFI::LengthHistogram(incfrac => 1);

while (<>) {
    chomp;
    $histo->addData($_);
}

$histo->saveToFile();


