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


my ($ssnIn, $n, $ssnOut, $incFrac, $outputDir, $scheduler, $dryRun, $queue, $mapDirName, $mapFileName);
my $result = GetOptions(
    "ssn-in=s"          => \$ssnIn,
    "n=s"               => \$n,
    "ssn-out=s"         => \$ssnOut,
    "inc-frac=i"        => \$incFrac,
    "out-dir=s"         => \$outputDir,
    "scheduler=s"       => \$scheduler,
    "dry-run"           => \$dryRun,
    "queue=s"           => \$queue,
    "map-dir-name=s"    => \$mapDirName,
    "map-file-name=s"   => \$mapFileName,
);

$usage=<<USAGE
usage: $0 -ssnin <filename> -n <positive integer> -ssnout <filename>
    -ssn-in         path to file of original ssn network to process
    -n              distance (+/-) to search for neighbors
    -ssn-out        output filename (not path) for colorized sequence similarity network
    -inc-frac       inc frac
    -out-dir        output directory
    -scheduler      scheduler type (default to torque, but also can be slurm)
    -dry-run        only generate the scripts, don't submit to queue
    -queue          the cluster queue to use
    -map-dir-name   the name of the sub-directory to use to output the list of uniprot IDs for each cluster (one file per cluster)
    -map-file-name  the name of the map file that lists uniprot ID, cluster #, and cluster color
USAGE
;

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

unless ($n > 0) {
    die "-n $n must be an integer greater than zero\n$usage";
}

if($incFrac=~/^\d+$/){
    $incFrac=$incFrac/100;
}else{
    if(defined $incFrac){
        die "incfrac must be an integer\n";
    }
    $incFrac=0.20;  
}


my $outputPath = "$ENV{PWD}/$outputDir";
mkdir $outputPath or die "Unable to create output directory $outputPath: $!" if not -d $outputPath ;
my $clusterDataPath = "$outputPath/$mapDirName";
mkdir $clusterDataPath or die "Unable to create output cluster data path $clusterDataPath: $!" if not -d $clusterDataPath;


my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new Biocluster::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryrun);


my $B = $SS->getBuilder();
$B->addAction("module load $dbModule");
$B->addAction("module load $gntModule");
$B->addAction("module list");
$B->addAction("cd $outputPath");
$B->addAction("makegnn.pl -n $n -incfrac $incFrac -ssnin $ssnIn -ssnout $outputPath/$ssnOut -data-dir $clusterDataPath -id-out $mapFileName -config $configFile");
$B->addAction("getfasta.pl -data-dir $clusterDataPath -config $configFile");

my $jobScript = "$outputPath/colorgnn.sh";
$B->renderToFile($jobScript);

my $jobId = $SS->submit($jobScript);
print "Color SSN job is $jobId\n";


