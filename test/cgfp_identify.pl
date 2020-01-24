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

use EFI::Job::CGFP::Identify;
my $jobBuilder = new EFI::Job::CGFP::Identify();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "cgfp-identify",
        "--ssn-in", $SSN_COLORED_SSN,
        "--ssn-out-name", "identify.xgmml",
    );

    return @a;
}




