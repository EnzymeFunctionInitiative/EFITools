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

use EFI::Job::GNT::GNN;
my $jobBuilder = new EFI::Job::GNT::GNN();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "gnn",
        "--ssn-in", $SSN_UNIPROT_DOMAIN,
    );

    return @a;
}




