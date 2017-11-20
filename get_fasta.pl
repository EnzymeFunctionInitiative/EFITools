#!/usr/bin/env perl

BEGIN {
    die "The efishared environment must be loaded before running this script" if not exists $ENV{EFISHARED} or not exists $ENV{EFIDBPATH};
    use lib $ENV{EFISHARED};
}

use Getopt::Long;
use File::Slurp;
use Capture::Tiny qw(:all);

use EFI::Database;
use EFI::GNN::Base;

#$configfile=read_file($ENV{'EFICFG'}) or die "could not open $ENV{'EFICFG'}\n";
#eval $configfile;

my ($result, $nodeDir, $fastaDir, $configFile, $allFastaFile);
$result = GetOptions(
    "node-dir=s"        => \$nodeDir,
    "out-dir=s"         => \$fastaDir,
    "all=s"             => \$allFastaFile,
    "config=s"          => \$configFile,
);

my $usage=<<USAGE
usage: $0 -data-dir <path_to_data_dir> -config <config_file>
    -node-dir       path to directory containing lists of IDs (one file/list per cluster number)
    -out-dir        path to directory to output fasta files to
    -all            path to file to put all sequences into
    -config         path to configuration file
USAGE
;


if (not -d $nodeDir) {
    die "The input data directory must be specified and exist.\n$usage";
}

mkdir $fastaDir or die "Unable to create $fastaDir: $!" if not -d $fastaDir;


my $db = new EFI::Database(config_file => $configFile);
my $dbh = $db->getHandle();

my $blastDbPath = $ENV{EFIDBPATH};
$allFastaFile = "$fastaDir/all.fasta" if not $allFastaFile;

my $pattern = $EFI::GNN::Base::ClusterUniProtIDFilePattern;

open ALL, ">$allFastaFile";

foreach my $file (sort file_sort glob("$nodeDir/$pattern*.txt")) {
    (my $clusterNum = $file) =~ s%^.*/$pattern(\d+)\.txt$%$1%;
    
    open FASTA, ">$fastaDir/cluster_$clusterNum.fasta";
    open NODES, $file;

    my $hasLines = 1;
    my $nodeCount = 0;

    my @ids = map { $_ =~ s/[\r\n]//g; $_ } read_file($file);

    print "Retrieving sequences for cluster $clusterNum...\n";

    while (scalar @ids) {
        my $batchLine = join(",", splice(@ids, 0, 1000));
        my ($fastacmdOutput, $fastaErr) = capture {
            system("fastacmd", "-d", "$blastDbPath/combined.fasta", "-s", $batchLine);
        };
        my @sequences = split /\n>/, $fastacmdOutput;
        $sequences[0] = substr($sequences[0], 1) if $#sequences >= 0 and substr($sequences[0], 0, 1) eq ">";
        foreach my $seq (@sequences) {
            if ($seq =~ s/^\w\w\|(\w{6,10})\|.*//) {
                my $accession = $1;
                my $sql = "select Organism,PFAM from annotations where accession = '$accession'";
                my $sth = $dbh->prepare($sql);
                $sth->execute();
                
                my $organism = "Unknown";
                my $pfam = "Unknown";

                my $row = $sth->fetchrow_hashref();
                if ($row) {
                    $organism = $row->{Organism};
                    $pfam = $row->{PFAM};
                }

                print FASTA ">$accession $clusterNum|$organism|$pfam$seq\n";
                print ALL ">$accession $clusterNum|$organism|$pfam$seq\n";
            }
        }
    }

    print "Done retrieving sequences!\n";

    close NODES;
    close FASTA;
}

close ALL;


$dbh->disconnect();


sub file_sort {
    (my $aa = $a) =~ s/^.*?(\d+)\.txt$/$1/;
    (my $bb = $b) =~ s/^.*?(\d+)\.txt$/$1/;
    return $aa <=> $bb;
}

