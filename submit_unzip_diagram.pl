#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}

use strict;

use FindBin;
use Getopt::Long;
use lib $FindBin::Bin . "/lib";

use EFI::SchedulerApi;
use EFI::Util qw(usesSlurm);


my ($diagramZipFile, $scheduler, $queue, $dryRun);
my $result = GetOptions(
    "diagram-file=s"    => \$diagramZipFile,
    "scheduler=s"       => \$scheduler,
    "queue=s"           => \$queue,
    "dryrun"            => \$dryRun,
);

my $usage = <<USAGE
usage: $0 -diagram-file <filename> [-scheduler <slurm|torque>] [-queue <queue_name>]
    -diagram-file       the file to output data to use for arrow data
    -scheduler          scheduler type (default to torque, but also can be slurm)
    -queue              the cluster queue to use
USAGE
;

if (not -f $diagramZipFile) {
    die "$usage";
}

if (not $ENV{'EFIGNN'}) {
    die "The efignt module must be loaded.";
}


my $outputDir = $ENV{PWD};
my $toolpath = $ENV{'EFIGNN'};
my $efiGnnMod = $ENV{'EFIGNNMOD'};

$diagramZipFile = "$outputDir/$diagramZipFile"  unless $diagramZipFile =~ /^\//;
$queue = "efi"                                  unless $queue =~ /\w/;

if ($diagramZipFile !~ /\.zip$/) {
    exit(0);
}

(my $diagramDbFile = $diagramZipFile) =~ s/\.zip$/.sqlite/g;


my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryRun);


my $B = $SS->getBuilder();
$B->addAction("module load $efiGnnMod");
$B->addAction("$toolpath/unzip_ssn.pl -in $diagramZipFile -out $diagramDbFile -out-ext sqlite");
$B->addAction("touch $outputDir/unzip.completed");
$B->renderToFile("submit_unzip_diagram.sh");
my $unzipjob = $SS->submit("submit_unzip_diagram.sh");

print "Job to unzip diagram is :\n $unzipjob";

