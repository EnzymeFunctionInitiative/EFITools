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

use EFI::Job::EST::Generate::FASTA;
my $jobBuilder = new EFI::Job::EST::Generate::FASTA();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "fasta",
        "--fasta-file", "$DATADIR/test.fasta",
        "--pfam", "PF05677",
        "--uniref-version", "90",
        "--use-fasta-headers",
    );

    return @a;
}




