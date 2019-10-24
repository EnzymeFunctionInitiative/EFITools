#!/usr/bin/env perl

BEGIN {
    die "The efishared environment must be loaded before running this script" if not exists $ENV{EFISHARED};
    die "The efidb environment must be loaded before running this script" if not exists $ENV{EFIDBPATH};
    use lib $ENV{EFISHARED};
}

use strict;
use warnings;

use Getopt::Long;
use File::Slurp;
use Scalar::Util qw(openhandle);
use Capture::Tiny qw(:all);
use FindBin;
use lib $FindBin::Bin . "/lib";

use EFI::Database;
use EFI::GNN::Base;

#$configfile=read_file($ENV{'EFICFG'}) or die "could not open $ENV{'EFICFG'}\n";
#eval $configfile;

my ($nodeDir, $fastaDir, $configFile, $useAllFiles, $domainFastaDir);
my $result = GetOptions(
    "node-dir=s"        => \$nodeDir,
    "out-dir=s"         => \$fastaDir,
    "use-all-files"     => \$useAllFiles,
    "domain-out-dir=s"  => \$domainFastaDir,
    "config=s"          => \$configFile,
);

my $usage=<<USAGE
usage: $0 -data-dir <path_to_data_dir> -config <config_file>
    -node-dir       path to directory containing lists of IDs (one file/list per cluster number)
    -out-dir        path to directory to output fasta files to
    -domain-out-dir path to directory to output fasta files with domain only. If this is present
                    will output both full sequence and sequence with domain extracted, into the
                    two separate folders (-out-dir and -domain-out-dir). Assumes that the
                    -node-dir is the list of nodes that includes the domain, not the normal
                    UniProt ID lists.
    -use-all-files  if present, will grab all files in tihe input node-dir rathern than just those
                    matching the specific pattern it is looking for
    -config         path to configuration file
USAGE
;


if (not -d $nodeDir) {
    die "The input data directory must be specified and exist.\n$usage";
}
if ($domainFastaDir and not $fastaDir) {
    die "When using -domain-out-dir, -out-dir must also be specified.";
} elsif (not $fastaDir) {
    die "-out-dir must be specified.";
}
if ($configFile and not -f $configFile and not exists $ENV{EFICONFIG} and not -f $ENV{EFICONFIG}) {
    die "Config file required in environment or as a parameter.\n$usage"
}

$configFile = $ENV{EFICONFIG} if not $configFile or not -f $configFile;


mkdir $fastaDir or die "Unable to create $fastaDir: $!" if $fastaDir and not -d $fastaDir;
mkdir $domainFastaDir or die "Unable to create $fastaDir: $!" if $domainFastaDir and not -d $domainFastaDir;



my $db = new EFI::Database(config_file => $configFile);
my $dbh = $db->getHandle();

my $blastDbPath = $ENV{EFIDBPATH};

my $pattern;
my $globPattern;
my $singletonPattern = "singleton_UniProt_IDs.txt";
if ($useAllFiles) {
    $globPattern = "*.txt";
} else {
    $pattern = "cluster_Uni*_IDs_";
    $globPattern = "$pattern*.txt";
}

my @files = sort file_sort glob("$nodeDir/$globPattern");
if (scalar @files) {
    (my $pat = $files[0]) =~ s%^.*cluster_(Uni[^_]+)(.*)_IDs.*\.txt%$1$2%;
    $singletonPattern = "singleton_${pat}_IDs.txt";
    $pattern = "cluster_${pat}_IDs_";
}


open ALL, ">$fastaDir/all.fasta" or die "Unable to write to $fastaDir/all.fasta: $!";
my $allDomFh;
if ($domainFastaDir) {
    open ALLDOM, ">$domainFastaDir/all.fasta" or die "Unable to write to $domainFastaDir/all.fasta: $!";
    $allDomFh = \*ALLDOM;
}

foreach my $file (@files) {
    my $clusterNum = $file;
    my $fastaFileName = "";
    if (not $useAllFiles) {
        $clusterNum =~ s%^.*/$pattern(\d+)\.txt$%$1%;
        $fastaFileName = "cluster_$clusterNum.fasta";
    } else {
        $clusterNum =~ s%^.*/([^/]+)\.txt$%$1%;
        $fastaFileName = "$clusterNum.fasta";
    }
    
    my %customHeaders;
    my @ids = map {
            my $id = $_;
            $id =~ s/[\r\n]//g;
            if ($id =~ m/\t/) {
                my ($idActual, $custom) = split(m/\t/, $id);
                $id = $idActual;
                $customHeaders{$id} = $custom;
            }
            $id;
        } read_file($file);

    next if not scalar @ids;

    my $domFh;
    if ($allDomFh and $ids[0] =~ m/:/) { # Check for domain.  In some cases we pass the domain parameter for all calls - for example when we can't determine the file type apriori (e.g. when input file is zipped)
        my $domFastaFileName = "cluster_domain_$clusterNum.fasta";
        open DOM_FASTA, ">", "$domainFastaDir/$domFastaFileName" or die "Unable to write to $domainFastaDir/$domFastaFileName: $!";
        $domFh = \*DOM_FASTA;
    }

    open FASTA, ">", "$fastaDir/$fastaFileName" or die "Unable to write to $fastaDir/$fastaFileName: $!";

    print "Retrieving sequences for cluster $clusterNum...\n";

    saveSequences($clusterNum, \*FASTA, $domFh, \*ALL, $allDomFh, \@ids, \%customHeaders);

    print "Done retrieving sequences!\n";

    close FASTA;
    close DOM_FASTA if $allDomFh;
}


my $inputSingletonFile = "$nodeDir/$singletonPattern";
if (-f $inputSingletonFile) {
    open FASTA, ">", "$fastaDir/singletons.fasta" or die "Unable to write to $fastaDir/singletons.fasta: $!";
    my $domFh;
    if ($domainFastaDir) {
        open FASTA_DOM, ">", "$domainFastaDir/singletons.fasta" or die "Unable to write to $domainFastaDir/singletons.fasta: $!";
        $domFh = \*FASTA_DOM;
    }
    
    my @ids = map { $_ =~ s/[\r\n]//g; $_ } read_file($inputSingletonFile);

    saveSequences(0, \*FASTA, $domFh, \*ALL, $allDomFh, \@ids, {});

    close FASTA_DOM if $domainFastaDir;
    close FASTA;
}


close ALL;
close ALLDOM if $domainFastaDir;

$dbh->disconnect();


sub file_sort {
    (my $aa = $a) =~ s/^.*?(\d+)\.txt$/$1/;
    (my $bb = $b) =~ s/^.*?(\d+)\.txt$/$1/;
    return $aa <=> $bb;
}

sub saveSequences {
    my $clusterNum = shift;
    my $outputFh = shift;
    my $domOutputFh = shift;
    my $allFh = shift;
    my $allDomFh = shift;
    my $idRef = shift;
    my $customHeaders = shift;
    
    my @ids = @{ $idRef }; # convert array ref to list

    my $hasDomain = scalar @ids and $ids[0] =~ m/:/;

    while (scalar @ids) {
        my @rawBatchIds = splice(@ids, 0, 1000);
        my @batchIds = map { my $a = $_; $a =~ s/:\d+:\d+$//; $a } @rawBatchIds;

        my %domExt;
        if ($allDomFh and $hasDomain) {
            %domExt  = map {
                            my @parts = split m/:/;
                            $parts[0] => [$parts[1], $parts[2]];
                           } @rawBatchIds;
        }

        my $batchLine = join(",", @batchIds);
        my ($fastacmdOutput, $fastaErr) = capture {
            system("fastacmd", "-d", "$blastDbPath/combined.fasta", "-s", $batchLine);
        };

        my @sequences = split /\n>/, $fastacmdOutput;
        $sequences[0] = substr($sequences[0], 1) if $#sequences >= 0 and substr($sequences[0], 0, 1) eq ">";
        foreach my $seq (@sequences) {
            if ($seq =~ s/^\w\w\|(\w{6,10})\|.*//) {
                my $accession = $1;
                my $customHeader = exists $customHeaders->{$accession} ? $customHeaders->{$accession} : "";
                writeSequence($accession, $clusterNum, $outputFh, $allFh, $seq, $customHeader);
                if ($allDomFh and $hasDomain) {
                    $seq = extractDomain($seq, $domExt{$accession});
                    my $domAcc = $accession . ":" . join(":", @{$domExt{$accession}});
                    writeSequence($domAcc, $clusterNum, $domOutputFh, $allDomFh, $seq, $customHeader);
                }
            }
        }
    }
}

sub writeSequence {
    my $accession = shift;
    my $clusterNum = shift;
    my $fastaFh = shift;
    my $allFh = shift;
    my $seq = shift;
    my $header = shift;

    if (not $header) {
        (my $sqlAcc = $accession) =~ s/:\d+:\d+$//;
        my $sql = "SELECT annotations.Organism, GROUP_CONCAT(PFAM.id) AS PFAM FROM annotations LEFT JOIN PFAM ON annotations.accession = PFAM.accession WHERE annotations.accession = '$sqlAcc'";
        my $sth = $dbh->prepare($sql);
        $sth->execute();
        
        my $organism = "Unknown";
        my $pfam = "Unknown";
    
        my $row = $sth->fetchrow_hashref();
        if ($row) {
            $organism = $row->{Organism};
            $pfam = $row->{PFAM};
        }

        $header = "$accession $clusterNum|$organism|$pfam";
    }

    $fastaFh->print(">$header$seq\n");
    $allFh->print(">$header$seq\n") if $allFh;
}

sub extractDomain {
    my $seq = shift;
    my $domRef = shift;

    my ($start, $end) = @$domRef;
    $seq =~ s/[\r\n]//g;

    if ($start >= 0 and $start < length($seq) and $end >= 0 and $end <= length($seq)) {
        my $len = $end - $start;
        $seq = substr($seq, $start-1, $len);
        my $fmtSeq = "";
        while ($seq) {
            $fmtSeq .= "\n" . substr($seq, 0, 80);
            if (length($seq) > 80) {
                $seq = substr($seq, 80);
            } else {
                $seq = "";
            }
        }
        return $fmtSeq;
    } else {
        return "\n$seq";
    }
}


