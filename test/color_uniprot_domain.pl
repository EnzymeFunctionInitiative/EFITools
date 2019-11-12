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

use EFI::Job::EST::Color;
my $jobBuilder = new EFI::Job::EST::Color();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "colorssn",
        "--ssn-in", $SSN_UNIPROT_DOMAIN,
    );

    return @a;
}




