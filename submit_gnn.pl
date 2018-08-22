#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}

use strict;
use warnings;

use FindBin;
use Getopt::Long;
use lib $FindBin::Bin . "/lib";

use EFI::SchedulerApi;
use EFI::Util qw(usesSlurm);
use EFI::Config;
use EFI::GNN::Base;


my ($ssnIn, $nbSize, $warningFile, $gnn, $ssnOut, $cooc, $stats, $pfamHubFile, $pfamDir, $pfamDirZip, $allPfamDir, $allPfamDirZip);
my ($idDir, $idZip, $idOutputFile, $fastaDir, $fastaZip, $noneDir, $noneZip, $dontUseNewNeighborMethod);
my ($scheduler, $dryRun, $queue, $gnnOnly, $noSubmit, $jobId, $arrowDataFile, $coocTableFile);
my ($hubCountFile, $configFile);
my $result = GetOptions(
    "ssnin=s"           => \$ssnIn,
    "n|nb-size=s"       => \$nbSize,
    "warning-file=s"    => \$warningFile,
    "gnn=s"             => \$gnn,
    "ssnout=s"          => \$ssnOut,
    "incfrac|cooc=i"    => \$cooc,
    "stats=s"           => \$stats,
    "pfam=s"            => \$pfamHubFile,
    "pfam-dir=s"        => \$pfamDir,
    "pfam-zip=s"        => \$pfamDirZip, # only used for GNT calls, non batch
    "all-pfam-dir=s"    => \$allPfamDir,
    "all-pfam-zip=s"    => \$allPfamDirZip, # only used for GNT calls, non batch
    "id-dir=s"          => \$idDir,
    "id-zip=s"          => \$idZip, # only used for GNT calls, non batch
    "id-out=s"          => \$idOutputFile,
    "fasta-dir=s"       => \$fastaDir,
    "fasta-zip=s"       => \$fastaZip,
    "none-dir=s"        => \$noneDir,
    "none-zip=s"        => \$noneZip, # only used for GNT calls, non batch
    "disable-nnm"       => \$dontUseNewNeighborMethod,
    "scheduler=s"       => \$scheduler,
    "dry-run"           => \$dryRun,
    "queue=s"           => \$queue,
    "gnn-only"          => \$gnnOnly,
    "no-submit"         => \$noSubmit,
    "job-id=s"          => \$jobId,
    "arrow-file=s"      => \$arrowDataFile,
    "cooc-table=s"      => \$coocTableFile,
    "hub-count-file=s"  => \$hubCountFile,
    "config=s"          => \$configFile,
);

my $usage = <<USAGE
usage: $0
    -ssnin              name of original ssn network to process
    -nb-size            distance (+/-) to search for neighbors
    -gnn                filename of genome neighborhood network output file
    -ssnout             output filename for colorized sequence similarity network
    -warning-file       output file that contains sequences without neighbors or matches
    -cooc               co-occurrence
    -stats              file to output tabular statistics to
    -pfam               file to output PFAM hub GNN to
    -id-dir             path to directory to output lists of IDs (one file/list per cluster number)
    -id-zip             path to a file to zip all of the output lists
    -pfam-dir           path to directory to output PFAM cluster data (one file/list per cluster number)
    -pfam-zip           path to a file to output zip file for PFAM cluster data
    -all-pfam-dir       path to directory to output PFAM cluster data (one file/list per cluster number), for all Pfams regardless of cooccurrence threshold
    -all-pfam-zip       path to a file to output zip file for PFAM cluster data, for all Pfams regardless of cooccurrence threshold
    -fasta-dir          path a directory output FASTA files
    -fasta-zip          path to a file to create compressed all FASTA files
    -id-out             path to a file to save the ID, cluster #, cluster color
    -config             configuration file for database info, etc.
    -scheduler          scheduler type (default to torque, but also can be slurm)
    -dry-run            only generate the scripts, don't submit to queue [boolean]
    -queue              the cluster queue to use
    -arrow-file         the file to output data to use for arrow data
    -cooc-table         the file to output co-occurrence (pfam v cluster) data to
    -hub-count-file     the file to output #sequences for each hub cluster in the GNN
    -no-submit          don't submit the job to the cluster, only create the job script [boolean]
    -gnn-only           only create the GNN, don't obtain FASTA or create diagrams, etc. [boolean]

For GNN only, this script can be run as follows, for example:

$0 -ssnin <input_filename> -gnn-only

This will create files for the gnn, warning, pfam hub, stats, and colored ssn outputs in the current
directory.  They will be named the same as the base name of the input ssn file.  The output name
and/or location can be overridden by using the various options above.

USAGE
;


die $usage if not $ssnIn;

if ((not defined $configFile or not -f $configFile) and not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
} elsif (not $configFile) {
    $configFile = $ENV{EFICONFIG};
}


my $toolpath = $ENV{'EFIGNN'};
my $efiGnnMod = $ENV{'EFIGNNMOD'};
my $efiDbMod = $ENV{'EFIDBMOD'};
my $defaultDir = $ENV{'PWD'};

(my $inputFileBase = $ssnIn) =~ s%^.*/([^/]+)$%$1%;
$inputFileBase =~ s/\.zip$//;
$inputFileBase =~ s/\.xgmml$//;

my $fullGntRun = defined $gnnOnly ? 0 : 1;
$noSubmit = 0                                                               if not defined $noSubmit;
$nbSize = 10                                                                if not defined $nbSize;
$cooc = 20                                                                  if not defined $cooc;
$gnn = "$defaultDir/${inputFileBase}_ssn_cluster_gnn.xgmml"                 if not $gnn;
$ssnOut = "$defaultDir/${inputFileBase}_coloredssn.xgmml"                   if not $ssnOut;
$pfamHubFile = "$defaultDir/${inputFileBase}_pfam_family_gnn.xgmml"         if not $pfamHubFile;
$warningFile = "$defaultDir/${inputFileBase}_nomatches_noneighbors.txt"     if not $warningFile;
$arrowDataFile = ""                                                         if not defined $arrowDataFile;
$queue = "efi"                                                              if not defined $queue or not $queue;
$jobId = ""                                                                 if not defined $jobId;
$stats = "$defaultDir/${inputFileBase}_stats.txt"                           if not $stats;


if ($fullGntRun) {
    $pfamDir = "$defaultDir/pfam-data"                                      if not $pfamDir;
    $pfamDir = "$defaultDir/pfam-data"                                      if not $pfamDir;
    $allPfamDir = "$defaultDir/all-pfam-data"                               if not $allPfamDir;
    $allPfamDir = "$defaultDir/all-pfam-data"                               if not $allPfamDir;
    $pfamDirZip = "$defaultDir/${inputFileBase}_pfam_mapping.zip"           if not $pfamDirZip;
    $idDir = "$defaultDir/cluster-data"                                     if not $idDir;
    $idZip = "$defaultDir/${inputFileBase}_UniProt_IDs.zip"                 if not $idZip;
    $idOutputFile = "$defaultDir/${inputFileBase}_mapping_table.txt"        if not $idOutputFile;
    $fastaDir = "$defaultDir/fasta"                                         if not $fastaDir;
    $fastaZip = "$defaultDir/${inputFileBase}_FASTA.zip"                    if not $fastaZip;
    $noneDir = "$defaultDir/pfam-none"                                      if not $noneDir;
    $noneZip = "$defaultDir/${inputFileBase}_no_pfam_neighbors.zip"         if not $noneZip;
#    die "stats is  not specified"  if not $stats;
#    die "pfam-dir is  not specified"  if not $pfamDir;
#    die "pfam-zip is  not specified"  if not $pfamDirZip;
#    die "id-dir is  not specified"  if not $idDir;
#    die "id-zip is  not specified"  if not $idZip;
#    die "id-out is  not specified"  if not $idOutputFile;
#    die "fasta-dir is  not specified"  if not $fastaDir;
#    die "fasta-zip is  not specified"  if not $fastaZip;
#    die "none-dir is  not specified"  if not $noneDir;
#    die "none-zip is  not specified"  if not $noneZip;
} else {
    $pfamDir = "" if not defined $pfamDir;
    $pfamDirZip = "" if not defined $pfamDirZip;
    $allPfamDir = "" if not defined $allPfamDir;
    $allPfamDirZip = "" if not defined $allPfamDirZip;
    $idDir = "" if not defined $idDir;
    $idZip = "" if not defined $idZip;
    $idOutputFile = "" if not defined $idOutputFile;
    $fastaDir = "" if not defined $fastaDir;
    $fastaZip = "" if not defined $fastaZip;
    $noneDir = "" if not defined $noneDir;
    $noneZip = "" if not defined $noneZip;
}

print "gnn mod is:$efiGnnMod\n";
print "efidb mod is:$efiDbMod\n";
print "ssnin is $ssnIn\n";
print "n|nb-size is $nbSize\n";
print "warning-file is $warningFile\n";
print "gnn is $gnn\n";
print "ssnout is $ssnOut\n";
print "incfrac|cooc is $cooc\n";
print "stats is $stats\n";
print "distance is $nbSize\n";
print "pfam is $pfamHubFile\n";
print "pfam-dir is $pfamDir\n";
print "pfam-zip is $pfamDirZip\n";
print "all-pfam-dir is $allPfamDir\n";
print "all-pfam-zip is $allPfamDirZip\n";
print "id-dir is $idDir\n";
print "id-zip is $idZip\n";
print "id-out is $idOutputFile\n";
print "fasta-dir is $fastaDir\n";
print "fasta-zip is $fastaZip\n";
print "none-dir is $noneDir\n";
print "none-zip is $noneZip\n";
print "arrow-file is $arrowDataFile\n";
print "job-id is $jobId\n";

unless($nbSize>0){
    die "-n $nbSize must be an integer greater than zero\n$usage";
}

my $outputDir = $ENV{PWD};


$ssnIn = "$outputDir/$ssnIn"                unless $ssnIn =~ /^\//;
$gnn = "$outputDir/$gnn"                    unless $gnn =~ /^\//;
$ssnOut = "$outputDir/$ssnOut"              unless $ssnOut =~ /^\//;
$stats = "$outputDir/$stats"                unless $stats =~ /^\//;
$pfamHubFile = "$outputDir/$pfamHubFile"    unless $pfamHubFile =~ /^\//;
if ($fullGntRun) {
    $pfamDir = "$outputDir/$pfamDir"            unless $pfamDir =~ /^\//;
    $pfamDirZip = "$outputDir/$pfamDirZip"      unless $pfamDirZip =~ /^\//;
    $allPfamDir = "$outputDir/$allPfamDir"      unless $allPfamDir =~ /^\//;
    $allPfamDirZip = "$outputDir/$allPfamDirZip" unless $allPfamDirZip =~ /^\//;
    $idDir = "$outputDir/$idDir"                unless $idDir =~ /^\//;
    $idZip = "$outputDir/$idZip"                unless $idZip =~ /^\//;
    $idOutputFile = "$outputDir/$idOutputFile"  unless $idOutputFile =~ /^\//;
    $noneDir = "$outputDir/$noneDir"            unless $noneDir =~ /^\//;
    $noneZip = "$outputDir/$noneZip"            unless $noneZip =~ /^\//;
}


if($cooc!~/^\d+$/){
    if(defined $cooc){
        die "incfrac must be an integer\n";
    }
    $cooc=20;  
}


unless(-s $ssnIn){
    die "cannot open ssnin file $ssnIn\n";
}

my $ssnInZip = "";
if ($ssnIn =~ /\.zip$/i) {
    $ssnInZip = $ssnIn;
    $ssnIn =~ s/\.zip$/\.xgmml/i;
}

(my $ssnName = $ssnOut) =~ s%^.*/([^/]+)\.xgmml$%$1%i;
my $ssnOutZip = "$outputDir/$ssnName.zip";
(my $gnnZip = $gnn) =~ s/\.xgmml$/.zip/i;
(my $pfamHubFileZip = $pfamHubFile) =~ s/\.xgmml$/.zip/i;
my $allFastaFile = "$fastaDir/all.fasta";
(my $arrowZip = $arrowDataFile) =~ s/\.sqlite/.zip/i if $arrowDataFile;
my $singletonsFastaFile = "$fastaDir/singletons.fasta";

my $jobNamePrefix = $jobId ? "${jobId}_" : "";

if ($fullGntRun) {
    mkdir $fastaDir or die "Unable to create output fasta data path $fastaDir: $!" if not -d $fastaDir;
}


my $cmdString = "$toolpath/cluster_gnn.pl " .
    "-nb-size $nbSize " . 
    "-cooc \"$cooc\" " .
    "-ssnin \"$ssnIn\" " . 
    "-ssnout \"$ssnOut\" " . 
    "-gnn \"$gnn\" " . 
    "-stats \"$stats\" " .
    "-warning-file \"$warningFile\" " .
    "-pfam \"$pfamHubFile\" "
    ;
if ($fullGntRun) {
    $cmdString .= 
        "-pfam-dir \"$pfamDir\" " .
        "-all-pfam-dir \"$allPfamDir\" " .
        "-id-dir \"$idDir\" " .
        "-id-out \"$idOutputFile\" " .
        "-none-dir \"$noneDir\" ";
    $cmdString .= " -arrow-file \"$arrowDataFile\"" if $arrowDataFile;
    $cmdString .= " -cooc-table \"$coocTableFile\"" if $coocTableFile;
    $cmdString .= " -hub-count-file \"$hubCountFile\"" if $hubCountFile;
}

my $info = {
    color_only => 0,
    node_data_path => $idDir,
    node_zip => $idZip,
    fasta_data_path => $fastaDir,
    fasta_zip => $fastaZip,
    ssn_out => $ssnOut,
    ssn_out_zip => $ssnOutZip,
    config_file => $configFile,
    fasta_tool_path => "$toolpath/get_fasta.pl",
    gnn => $gnn,
    gnn_zip => $gnnZip,
    pfamhubfile => $pfamHubFile,
    pfamhubfile_zip => $pfamHubFileZip,
    pfam_dir => $pfamDir,
    pfam_zip => $pfamDirZip,
    all_pfam_dir => $allPfamDir,
    all_pfam_zip => $allPfamDirZip,
    none_dir => $noneDir,
    none_zip => $noneZip,
    all_fasta_file => $allFastaFile,
    singletons_file => $singletonsFastaFile,
};

$info->{arrow_zip} = $arrowZip if $arrowZip;
$info->{arrow_file} = $arrowDataFile if $arrowDataFile;


my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryRun);


my $B = $SS->getBuilder();

$B->resource(1, 1, "150gb");
$B->addAction("source /etc/profile");
$B->addAction("module load $efiDbMod");
$B->addAction("module load $efiGnnMod");
$B->addAction("export BLASTDB=$outputDir/blast");
$B->addAction("$toolpath/unzip_file.pl -in $ssnInZip -out $ssnIn") if $ssnInZip =~ /\.zip/i;
$B->addAction($cmdString);
if ($fullGntRun) {
    EFI::GNN::Base::addFileActions($B, $info);
    $B->addAction("\n\nmkdir \$BLASTDB");
    $B->addAction("cd \$BLASTDB");
    $B->addAction("formatdb -i $allFastaFile -n database -p T -o T");
}
$B->addAction("\n\n$toolpath/save_version.pl > $outputDir/gnn.completed");

$B->jobName("${jobNamePrefix}submit_gnn");
$B->renderToFile("submit_gnn.sh");

if (not $noSubmit) {
    my $gnnjob = $SS->submit("submit_gnn.sh");
    chomp $gnnjob;
    print "Job to make gnn network is :\n $gnnjob";
}

