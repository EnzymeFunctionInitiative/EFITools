#!/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use FindBin;
use File::Temp;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use Setup;


my $testDir = $ARGV[0] // "";
die "Require an existing job results directory" if not $testDir or not -d $testDir;

my $test = new Setup(getArgs(), {job_dir => $testDir});

use EFI::Job::EST::Analyze;
my $jobBuilder = new EFI::Job::EST::Analyze();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "analyze",
        "--filter", "eval",
        "--minval", 23,
    );

    return @a;
}




