#!/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use FindBin;
use File::Temp;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use Setup;


my $testDir = $ENV{PARENT} // "";
$testDir = "$TMP/$testDir" if $testDir;
die "Require an existing job results directory" if not $testDir or not -d $testDir;

my $test = new Setup(getArgs(), {job_dir => $testDir});

use EFI::Job::CGFP::Identify;
my $jobBuilder = new EFI::Job::CGFP::Identify();

$test->runTest($jobBuilder);


sub getArgs {
    my @a = (
        "cgfp-quantify",
        "--ssn-in", "$testDir/results/identify.xgmml",
        "--ssn-out-name", "quantify.xgmml",
        "--quantify-dir", "quantify-test",
        "--metagenome-db", "hmp",
        "--metagenome-ids", "SRS011061,SRS011090,SRS011098,SRS011126,SRS011132",
    );

    return @a;
}




