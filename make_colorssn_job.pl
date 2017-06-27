#!/usr/bin/env perl

BEGIN {
    die "The efiest and efignn environments must be loaded before running this script" if not exists $ENV{EFIEST} or not exists $ENV{EFIGNN};
}

use Getopt::Long;
#use List::MoreUtils qw{apply uniq any} ;
#use DBD::mysql;
#use IO;
#use XML::Writer;
#use File::Slurp;
#use XML::LibXML::Reader;
#use List::Util qw(sum);
#use Array::Utils qw(:all);

use lib $ENV{EFIEST} . "/lib";
use Biocluster::Database;
use Biocluster::SchedulerApi;
use Biocluster::Util qw(usesSlurm);
use Biocluster::Config;


my ($ssnIn, $nbSize, $ssnOut, $cooc, $outputDir, $scheduler, $dryRun, $queue, $mapDirName, $mapFileName);
my $result = GetOptions(
    "ssn-in=s"          => \$ssnIn,
    "ssn-out=s"         => \$ssnOut,
    "out-dir=s"         => \$outputDir,
    "scheduler=s"       => \$scheduler,
    "dry-run"           => \$dryRun,
    "queue=s"           => \$queue,
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

my $estPath = $ENV{EFIEST};
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


my $outputPath = $ENV{PWD} . "/$outputDir";
mkdir $outputPath or die "Unable to create output directory $outputPath: $!" if not -d $outputPath ;
my $clusterDataPath = "$outputPath/$mapDirName";
$clusterDataPath =~ s%/+$%%;
mkdir $clusterDataPath or die "Unable to create output cluster data path $clusterDataPath: $!" if not -d $clusterDataPath;
my $nodeDataPath = "$clusterDataPath/nodes";
mkdir $nodeDataPath or die "Unable to create output node data path $nodeDataPath: $!" if not -d $nodeDataPath;
my $fastaDataPath = "$clusterDataPath/fasta";
mkdir $fastaDataPath or die "Unable to create output fasta data path $fastaDataPath: $!" if not -d $fastaDataPath;


my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new Biocluster::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryrun);


my $B = $SS->getBuilder();
$B->addAction("$str");
$B->addAction("module load $dbModule");
$B->addAction("module load $gntModule");
$B->addAction("cd $outputPath");
$B->addAction("unzip -p $ssnInZip > $ssnIn") if $ssnInZip =~ /\.zip/i;
$B->addAction("clustergnn.pl -nb-size 10 -cooc 20 -ssnin $ssnIn -ssnout $outputPath/$ssnOut -data-dir $nodeDataPath -id-out ${ssnName}_$mapFileName -config $configFile");
$B->addAction("getfasta.pl -node-dir $nodeDataPath -out-dir $fastaDataPath -config $configFile");
$B->addAction("zip -j -r $outputPath/${ssnName}_nodes.zip $nodeDataPath");
$B->addAction("zip -j -r $outputPath/${ssnName}_fasta.zip $fastaDataPath");
#this is done in clustergnn.pl $B->addAction("zip -j $outputPath/$ssnOutZip $outputPath/$ssnOut");
$B->addAction("touch $outputPath/1.out.completed");

my $jobScript = "$outputPath/colorgnn.sh";
$B->renderToFile($jobScript);

my $jobId = $SS->submit($jobScript);
print "Color SSN job is:\n $jobId";


