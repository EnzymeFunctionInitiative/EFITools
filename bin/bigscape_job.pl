#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib abs_path("$FindBin::Bin/../lib");

use Getopt::Long;

use EFI::SchedulerApi;
use EFI::Util qw(usesSlurm);


my ($diagramFile, $dryRun, $scheduler, $queue, $bigscapeDir, $clusterInfoFile, $updatedDiagram,
    $bigscapeWindow, $configFile, $efiJobId);
my $result = GetOptions(
    "diagram-file=s"            => \$diagramFile,
    "updated-diagram-file=s"    => \$updatedDiagram,
    "cluster-info-file=s"       => \$clusterInfoFile,
    "bigscape-dir=s"            => \$bigscapeDir,
    "window=i"                  => \$bigscapeWindow,
    "dryrun"                    => \$dryRun,
    "scheduler=s"               => \$scheduler,
    "queue=s"                   => \$queue,
    "job-id=s"                  => \$efiJobId,
    "config=s"                  => \$configFile,
);

my $usage = <<USAGE
usage: $0 -diagram-file <filename> [-bigscape-dir <directory>] [-updated-diagram-file <filename>]
    [-cluster-info <filename>] [-scheduler <slurm|torque>] [-queue <queue_name>] [-config <filename>]

    -diagram-file           path to the input diagram file to use
    -bigscape-dir           path to the directory to put BiG-SCAPE data into; defaults to a directory
                            'bigscape' in the same directory as the input file
    -updated-diagram-file   path to the output diagram file that contains updated sort orders; defaults
                            to the name of the diagram file with '.bigscape' appended
    -cluster-info-file      path to the output file containing the info on the BiG-SCAPE clans;
                            defaults to the name of the diagram file with '.cluster-info' appended
    -window                 the number of genes on either side of the query gene to include in the
                            analysis (must be smaller than the window size in the original diagram)

    -config                 path to config file (if not provided, assumed from environment)
    -scheduler              scheduler type (default to torque, but also can be slurm)
    -queue                  the cluster queue to use
    -dryrun                 if this flag is present, the jobs aren't executed but the job scripts
                            are output to the terminal
USAGE
;


die "The efitools module must be loaded." if not $ENV{EFI_TOOL_MOD};
die "The efidb module must be loaded." if not $ENV{EFI_DB_MOD};


if ((not defined $configFile or not -f $configFile) and not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
} elsif (not defined $configFile or not -f $configFile) {
    $configFile = $ENV{EFICONFIG};
}

die "$usage" if not -f $diagramFile;

$queue = "efi"                                  unless $queue =~ /\w/;
$efiJobId = ""                                  unless defined $efiJobId;


my $toolPath = abs_path("$FindBin::Bin/../sbin");
my $toolMod = $ENV{EFI_TOOL_MOD};
my $blastDb = $ENV{EFI_DB_PATH} . "/combined.fasta";
my $dbMod = $ENV{EFI_DB_MOD};

if (not $bigscapeDir) {
    if ($diagramFile !~ m/\//) {
        $bigscapeDir = ".";
    } else {
        ($bigscapeDir = $diagramFile) =~ s%^(.*)/[^/]+$%$1%;
    }
    $bigscapeDir .= "/bigscape";
}

if (not $updatedDiagram) {
    $updatedDiagram = "$diagramFile.bigscape";
}

if (not $clusterInfoFile) {
    $clusterInfoFile = "$diagramFile.bigscape-clusters";
}

my $outputDir = "$bigscapeDir/fasta";
my $errorFile = "$bigscapeDir/error.message";
my $jobCompletedFile = "$bigscapeDir/COMPLETED";
my $jobErrorFile = "$bigscapeDir/job.error";
my $logDir = "$bigscapeDir/log";
my $metaFile = "cluster.metadata";
my $bigscapeWindowArg = (defined $bigscapeWindow and $bigscapeWindow > 0) ? "-window $bigscapeWindow" : "";

mkdir $bigscapeDir if not -d $bigscapeDir;
mkdir $logDir if not -d $logDir;

my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());

my %schedArgs = (type => $schedType, queue => $queue, resource => [1, 24, "50GB"], dryrun => $dryRun);
$schedArgs{output_base_dirpath} = $logDir;


my $jobNamePrefix = $efiJobId ? "${efiJobId}_" : "";

my $SS = new EFI::SchedulerApi(%schedArgs);


my $B = $SS->getBuilder();
$B->setScriptAbortOnError(0);
$B->addAction("rm -rf $bigscapeDir/fasta") if (-d "$bigscapeDir/fasta");
$B->addAction("rm -rf $bigscapeDir/run") if (-d "$bigscapeDir/run");
$B->addAction("mkdir -p $outputDir");
$B->addAction("rm -f $errorFile");
$B->addAction("touch $errorFile");
$B->addAction("module load $toolMod");
$B->addAction("module load $dbMod");
$B->addAction("$toolPath/extract_ids_from_diagrams.pl -diagram-file $diagramFile -metadata-file $metaFile -output-dir $outputDir $bigscapeWindowArg");
$B->addAction("source /home/n-z/noberg/miniconda2/bin/activate /home/n-z/noberg/miniconda2/envs/bigscape");
$B->addAction("date");
$B->addAction("for dirName in \$( ls $outputDir ); do");
$B->addAction("    outDir=\"$outputDir/\$dirName\"");
$B->addAction("    bsDir=\"$bigscapeDir/run/\$dirName\"");
$B->addAction("    mkdir -p \$outDir");
$B->addAction("    mkdir -p \$bsDir");
$B->addAction("    $toolPath/get_fasta.pl -node-dir \$outDir -out-dir \$outDir -use-all-files");
$B->addAction("    $toolPath/validate_fasta.pl -input-dir \$outDir -metadata-file \$outDir/$metaFile");
$B->addAction("    python /home/n-z/noberg/bigscape/BiG-SCAPE/bigscape.py -i \$outDir -o \$bsDir --cores 24 --clans --clan_cutoff 0.95 0.95 --pfam_dir /home/n-z/noberg/bigscape/hmm --precomputed_fasta --no_classify --mix --run_name \$dirName");
$B->addAction("done");
$B->addAction("cp $diagramFile $updatedDiagram");
$B->addAction("$toolPath/update_diagram_order.pl -diagram-file $updatedDiagram -bigscape-dir $bigscapeDir -cluster-file $clusterInfoFile -config $configFile");
$B->addAction("touch $jobCompletedFile");
$B->addAction("date");



my $jobId;


my $jobName = "${jobNamePrefix}bigscape";
my $jobScript = "$jobName.sh";
$B->jobName($jobName);
$B->renderToFile($jobScript);
$jobId = $SS->submit($jobScript);
chomp $jobId;

print "BiG-SCAPE job is :\n $jobId";



sub addBashErrorCheck {
    my ($B, $markAbort, $outputFile) = @_;

    if ($markAbort) {
        $B->addAction("if [ \$? -ne 0 ]; then");
        $B->addAction("    touch $jobErrorFile");
        $B->addAction("fi");
    }
    $B->addAction("if [ ! -f \"$outputFile\" ]; then");
    $B->addAction("    touch $jobErrorFile");
    $B->addAction("fi");
    $B->addAction("touch $jobCompletedFile");

    $B->addAction("");
}



