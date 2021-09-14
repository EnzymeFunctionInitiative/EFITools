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

use EFI::Job::EST::Generate::Family;
my $jobBuilder = new EFI::Job::EST::Generate::Family();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "family",
        "--pfam", "PF05677",
        "--domain",
    );

    return @a;
}




