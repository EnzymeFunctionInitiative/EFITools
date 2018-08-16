#!/usr/bin/env perl

BEGIN {
    die "The efishared and efignn environments must be loaded before running this script" if not exists $ENV{EFISHARED} or not exists $ENV{EFIGNN};
    use lib $ENV{EFISHARED};
}

use Getopt::Long;

use EFI::Database;
use EFI::SchedulerApi;
use EFI::Util qw(usesSlurm);
use EFI::Config;
use EFI::GNN::Base;


my ($ssnIn, $nbSize, $ssnOut, $cooc, $outputDir, $scheduler, $dryRun, $queue, $mapDirName, $mapFileName, $jobId);
my $result = GetOptions(
    "ssn-in=s"          => \$ssnIn,
    "ssn-out=s"         => \$ssnOut,
    "out-dir=s"         => \$outputDir,
    "scheduler=s"       => \$scheduler,
    "dry-run"           => \$dryRun,
    "queue=s"           => \$queue,
    "job-id=s"          => \$jobId,
    "map-dir-name=s"    => \$mapDirName,
    "map-file-name=s"   => \$mapFileName,
#    "nb-size=s"         => \$nbSize,
#    "cooc=i"            => \$cooc,
);

$usage=<<USAGE
usage: $0 -ssnin <filename> -n <positive integer> -ssnout <filename>
    -ssn-in         path to file of original ssn network to process
    -ssn-out        output filename (not path) for colorized sequence similarity network
    -out-dir        output directory
    -scheduler      scheduler type (default to torque, but also can be slurm)
    -dry-run        only generate the scripts, don't submit to queue
    -queue          the cluster queue to use
    -map-dir-name   the name of the sub-directory to use to output the list of uniprot IDs for each cluster (one file per cluster)
    -map-file-name  the name of the map file that lists uniprot ID, cluster #, and cluster color
USAGE
;
#    -nb-size        distance (+/-) to search for neighbors
#    -cooc           inc frac

my $dbModule = $ENV{EFIDBMOD};
my $gntPath = $ENV{EFIGNN};
my $gntModule = $ENV{EFIGNNMOD};


if (not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
}
my $configFile = $ENV{EFICONFIG};

unless (-s $ssnIn) {
    die "-ssnin $ssnIn does not exist or has a zero size\n$usage";
}

# We don't need these parameters to just generate a colored SSN
#unless ($nbSize > 0) {
#    die "-n $nbSize must be an integer greater than zero\n$usage";
#}
#if($cooc=~/^\d+$/){
#    $cooc=$cooc/100;
#}else{
#    if(defined $cooc){
#        die "incfrac must be an integer\n";
#    }
#    $cooc=0.20;  
#}

if (not $ssnOut) {
    ($ssnOut = $ssnIn) =~ s/^.*?([^\/]+)$/$1/;
    $ssnOut =~ s/\.(xgmml|zip)$/_colored.xgmml/i;
}
(my $ssnName = $ssnOut) =~ s/\.xgmml$//i;
my $ssnOutZip = "$ssnName.zip";

my $ssnInZip = $ssnIn;
if ($ssnInZip =~ /\.zip$/i) {
    $ssnIn =~ s/\.zip$/.xgmml/i;
}


$jobId = "" unless defined $jobId;
my $jobNamePrefix = $jobId ? "${jobId}_" : "";


my $outputPath = $ENV{PWD} . "/$outputDir";
mkdir $outputPath or die "Unable to create output directory $outputPath: $!" if not -d $outputPath ;
my $clusterDataPath = "$outputPath/$mapDirName";
$clusterDataPath =~ s%/+$%%;
mkdir $clusterDataPath or die "Unable to create output cluster data path $clusterDataPath: $!" if not -d $clusterDataPath;
my $nodeDataPath = "$clusterDataPath/nodes";
mkdir $nodeDataPath or die "Unable to create output node data path $nodeDataPath: $!" if not -d $nodeDataPath;
my $fastaDataPath = "$clusterDataPath/fasta";
mkdir $fastaDataPath or die "Unable to create output fasta data path $fastaDataPath: $!" if not -d $fastaDataPath;
my $allFastaFile = "$fastaDataPath/all.fasta";
my $singletonsFastaFile = "$fastaDataPath/singletons.fasta";
my $inputSeqsFile = "$clusterDataPath/sequences.fasta";

my $nodeDataZip = "$outputPath/${ssnName}_UniProt_IDs.zip";
my $fastaZip = "$outputPath/${ssnName}_FASTA.zip";

my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryRun);


my $fileInfo = {
    color_only => 1,
    node_data_path => $nodeDataPath,
    node_zip => $nodeDataZip,
    fasta_data_path => $fastaDataPath,
    fasta_zip => $fastaZip,
    fasta_tool_path => "$gntPath/get_fasta.pl",
    ssn_out => "$outputPath/$ssnOut",
    ssn_out_zip => "$outputPath/$ssnOutZip",
    config_file => $configFile,
    tool_path => $gntPath,
    all_fasta_file => $allFastaFile,
    singletons_file => $singletonsFastaFile,
    input_seqs_file => $inputSeqsFile,
};


my $B = $SS->getBuilder();

$B->resource(1, 1, "90gb");
$B->addAction("$str");
$B->addAction("module load $dbModule");
$B->addAction("module load $gntModule");
$B->addAction("cd $outputPath");
$B->addAction("$gntPath/unzip_file.pl -in $ssnInZip -out $ssnIn") if $ssnInZip =~ /\.zip/i;
$B->addAction("$gntPath/cluster_gnn.pl -nb-size 10 -cooc 20 -ssnin $ssnIn -ssnout $outputPath/$ssnOut -id-dir $nodeDataPath -id-out ${ssnName}_$mapFileName -config $configFile");
EFI::GNN::Base::addFileActions($B, $fileInfo);
$B->addAction("touch $outputPath/1.out.completed");

my $jobName = "${jobNamePrefix}colorgnn";
my $jobScript = "$outputPath/$jobName.sh";
$B->jobName($jobName);
$B->renderToFile($jobScript);

my $jobId = $SS->submit($jobScript);
print "Color SSN job is:\n $jobId";


