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
use EFI::GNN::Arrows;


my ($diagramZipFile, $blastSeq, $evalue, $maxNumSeq, $outputFile, $scheduler, $queue, $dryRun,
    $legacy, $title, $nbSize, $idFile, $jobType, $fastaFile, $jobId);
my $result = GetOptions(
    "zip-file=s"            => \$diagramZipFile,

    "blast=s"               => \$blastSeq,
    "evalue=n"              => \$evalue,
    "max-seq=n"             => \$maxNumSeq,
    "nb-size=n"             => \$nbSize, # neighborhood size

    "id-file=s"             => \$idFile,
    "fasta-file=s"          => \$fastaFile,

    "output=s"              => \$outputFile,
    "title=s"               => \$title,
    "job-type=s"            => \$jobType,

    "job-id=s"              => \$jobId,
    "scheduler=s"           => \$scheduler,
    "queue=s"               => \$queue,
    "dryrun"                => \$dryRun,
    "legacy"                => \$legacy,
);

my $usage = <<USAGE
usage: $0 -diagram-file <filename> [-scheduler <slurm|torque>] [-queue <queue_name>]
    -zip-file           the file to output data to use for arrow data

    -blast              the sequence for Option A, which uses BLAST to get similar sequences
    -evalue             the evalue to use for BLAST
    -max-seq            the maximum number of sequences to return from the BLAST
    -nb-size            the neighborhood window on either side of the query sequence

    -id-file            file containing a list of IDs to use to generate the diagrams
    -fasta-file         file containing FASTA sequences with headers; we extract the IDs from
                        the headers and use those IDs to generate the diagrams

    -output             output sqlite file for Options A-D
    -title              the job title to save in the output file
    -job-type           the string to put in for the job type (used by the web app)

    -scheduler          scheduler type (default to torque, but also can be slurm)
    -queue              the cluster queue to use
    -dryrun             if this flag is present, the jobs aren't executed but the job scripts
                        are output to the terminal
    -legacy             if this flag is present, the legacy modules are used
USAGE
;

my $diagramVersion = $EFI::GNN::Arrows::Version;


if (not -f $diagramZipFile and not $blastSeq and not -f $idFile and not -f $fastaFile) {
    die "$usage";
}

if (not $ENV{'EFIGNN'}) {
    die "The efignt module must be loaded.";
}

if (not $ENV{"EFIDBMOD"}) {
    die "The efidb module must be loaded.";
}

my $blastMod = $legacy ? "blast" : "BLAST";
if ($blastSeq and $outputFile) {
    if (not $ENV{"BLASTDB"}) {
        die "The $blastMod module must be loaded.";
    } elsif (not $ENV{"EFIDBPATH"}) {
        die "The efidb module must be loaded.";
    }
}


my $outputDir = $ENV{PWD};
my $toolpath = $ENV{"EFIGNN"};
my $efiGnnMod = $ENV{"EFIGNNMOD"};
my $blastDb = $ENV{"EFIDBPATH"} . "/combined.fasta";
my $dbMod = $ENV{"EFIDBMOD"};


$diagramZipFile = "$outputDir/$diagramZipFile"  if $diagramZipFile and $diagramZipFile !~ /^\//;
$queue = "efi"                                  unless $queue =~ /\w/;
$evalue = 5                                     if not $evalue;
$maxNumSeq = 200                                if not $maxNumSeq;
$title = ""                                     if not $title;
$nbSize = 10                                    if not $nbSize;
$jobId = ""                                     if not defined $jobId;

#if ($diagramZipFile and $diagramZipFile !~ /\.zip$/) {
#    print "Not unzipping a file that doesn't end in zip ($diagramZipFile)\n";
#    exit(0);
#}

(my $diagramDbFile = $diagramZipFile) =~ s/\.zip$/.sqlite/g;

my $stderrFile = "$outputDir/stderr.log";
my $jobCompletedFile = "$outputDir/job.completed";
my $jobErrorFile = "$outputDir/job.error";
my $jobNamePrefix = $jobId ? "${jobId}_" : "";


my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1, "50GB"], dryrun => $dryRun);


my $titleArg = $title ? "-title \"$title\"" : "";


my $B = $SS->getBuilder();
$B->addAction("rm -f $stderrFile");
$B->addAction("touch $stderrFile");
$B->addAction("module load $efiGnnMod");
$B->addAction("module load $dbMod");

my $jobId;


###################################################################################################
# This job runs a BLAST on the input sequence, then extracts the sequence IDs from the output BLAST
# and then finds all of the neighbors for those IDs and creates the sqlite database from that.
if ($blastSeq) {
    $jobType = "BLAST" if not $jobType;

    my $seqFile = "$outputDir/query.fa";
    my $blastOutFile = "$outputDir/blast.raw";
    my $blastIdListFile = "$outputDir/blast.ids";

    open QUERY, "> $seqFile" or die "Unable to open $outputDir/query.fa for writing: $!";
    print QUERY $blastSeq;
    close QUERY;

    $B->resource(1, 1, "70gb");
    $B->addAction("module load $blastMod");
    $B->addAction("blastall -p blastp -i $seqFile -d $blastDb -m 8 -e $evalue -b $maxNumSeq -o $blastOutFile");
    #$B->addAction("grep -v '#' $blastOutFile | cut -f 2,11,12 | sort -k3,3nr | cut -d'|' -f2 > $blastIdListFile");
    $B->addAction("grep -v '#' $blastOutFile | cut -f 2,11,12 | sort -k3,3nr | sed 's/[\t ]\\{1,\\}/|/g' | cut -d'|' -f2,4 > $blastIdListFile");
    $B->addAction("create_diagram_db.pl -id-file $blastIdListFile -db-file $outputFile -blast-seq-file $seqFile -job-type $jobType $titleArg -nb-size $nbSize");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");

    addBashErrorCheck($B, 1, $outputFile);
}

elsif ($idFile) {
    $jobType = "ID_LOOKUP" if not $jobType;

    $B->resource(1, 1, "10gb");
    $B->addAction("create_diagram_db.pl -id-file $idFile -db-file $outputFile -job-type $jobType $titleArg -nb-size $nbSize -do-id-mapping");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");

    addBashErrorCheck($B, 0, $outputFile);
}

elsif ($fastaFile) {
    $jobType = "FASTA" if not $jobType;

    my $tempIdFile = "$outputFile.temp-ids";

    $B->resource(1, 1, "10gb");
    $B->addAction("extract_ids_from_fasta.pl -fasta-file $fastaFile -output-file $tempIdFile");
    $B->addAction("create_diagram_db.pl -id-file $tempIdFile -db-file $outputFile -job-type $jobType $titleArg -nb-size $nbSize -do-id-mapping");
    $B->addAction("rm $tempIdFile");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");
    
    addBashErrorCheck($B, 0, $outputFile);
}

else {
    $jobType = "unzip";
    $B->resource(1, 1, "5gb");
    ###################################################################################################
    # This job simply unzips the file.
    if ($diagramZipFile =~ m/\.zip$/i) {
        $B->addAction("$toolpath/unzip_file.pl -in $diagramZipFile -out $outputFile -out-ext sqlite 2> $stderrFile");
    }
    $B->addAction("$toolpath/check_diagram_version.pl -db-file $outputFile -version $diagramVersion -version-file $outputDir/diagram.version");
    addBashErrorCheck($B, 1, $outputFile);
}



$jobType = lc $jobType;

my $jobName = "${jobNamePrefix}diagram_$jobType";
my $jobScript = "$jobName.sh";

$B->jobName($jobName);
$B->renderToFile($jobScript);
$jobId = $SS->submit($jobScript);
chomp $jobId;

print "Diagram job ($jobType) is :\n $jobId";



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



