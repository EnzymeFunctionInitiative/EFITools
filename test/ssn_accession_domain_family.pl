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

use EFI::Job::EST::Generate::Accession;
my $jobBuilder = new EFI::Job::EST::Generate::Accession();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "accession",
        "--accession-file", "$DATADIR/uniprot_ids.txt",
        "--domain",
        "--domain-family", "PF04055",
    );

    return @a;
}




