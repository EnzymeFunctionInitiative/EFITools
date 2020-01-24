#!/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use FindBin;
use File::Temp;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use Setup;


# This line precedes the target lib.
my $test = new Setup(getArgs());

use EFI::Job::GNT::GND;
my $jobBuilder = new EFI::Job::GNT::GND();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "gnd",
        "--output", "blast_result.sqlite",
        "--blast-seq", "$DATADIR/sequence.txt",
    );

    return @a;
}




