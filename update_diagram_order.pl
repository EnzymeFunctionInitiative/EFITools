#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


use strict;
use DBI;
use Getopt::Long;
use FindBin;
use lib $FindBin::Bin . "/lib";

use EFI::GNN::Arrows;
use EFI::GNN::ColorUtil;
use EFI::Database;

my ($inputFile, $bigscapeDir, $clusterFile, $configFile);
my $result = GetOptions(
    "diagram-file=s"        => \$inputFile,
    "bigscape-dir=s"        => \$bigscapeDir,
    "cluster-file=s"        => \$clusterFile,
    "config=s"              => \$configFile,
);

my $usage = <<USAGE;
$0 -diagram-file INPUT_FILE -bigscape-dir DIRECTORY -config CONFIG_FILE [-cluster-file OUTPUT_CLUSTER_FILE]

    -diagram-file       path to input diagram file
    -bigscape-dir       path to directory to read BiG-SCAPE data from
    -cluster-file       path to file to output cluster information (tabular)
    -config             path to config file so we can get colors from database (required
                        if -cluster-file is specified)

USAGE

die "$usage" if not -f $inputFile or not -d $bigscapeDir;


my $dbh = DBI->connect("dbi:SQLite:dbname=$inputFile","","");

my $sql = "SELECT * FROM $EFI::GNN::Arrows::AttributesTable";
my $sth = $dbh->prepare($sql);
$sth->execute();

my %groupData;

while (my $row = $sth->fetchrow_hashref()) {
    $groupData{$row->{cluster_num}}->{$row->{accession}} = {};
}


my %clusterData;


foreach my $clusterNum (keys %groupData) {
    my $runName = "cluster_$clusterNum";
    my $runDir = "$bigscapeDir/run/$runName";
    next if not -d $runDir;

    my $netDir = "$runDir/network_files/$runName";
    my @files = glob("$netDir/*_clans_*");
    next if not scalar @files;

    my $clanFile = $files[0];

    my @data;

    my %clusterSize;

    open CLAN, $clanFile;
    while (my $line = <CLAN>) {
        chomp $line;
        $line =~ s/#.*$//;
        $line =~ s/^\s*(.*?)\s*$/$1/;
        next if not $line;

        my ($clusterName, $clanNum, $famNum) = split(m/\t/, $line);
        $clusterSize{$clanNum} = 0 if not exists $clusterSize{$clanNum};
        $clusterSize{$clanNum}++;
        push @data, [$clusterName, $clanNum, $famNum, \%clusterSize];
    }
    close CLAN;

    @data = sort sortFn @data;

    my $sql = "UPDATE attributes SET sort_order = 999999 WHERE cluster_num = $clusterNum";
    $dbh->do($sql); # Make sure that the ones that are singletons appear at the end.

    my $count = 0;
    foreach my $line (@data) {
        my $sql = "UPDATE attributes SET sort_order = $count WHERE cluster_num = $clusterNum AND accession = '$line->[0]'";
        push @{$clusterData{$clusterNum}}, [$line->[0], $line->[1], $line->[2], $count];
        print $sql, "\n";
        $dbh->do($sql);
        $count++;
    }
}

if ($clusterFile) {
    
    my $colorUtil = getColors();

    open CLUSTER, "> $clusterFile" or die "Unable to open cluster file $clusterFile: $!";
    
    my @headers = ("ID", "ClusterNum", "Accession", "ClanNumInCluster", "FamilyNumInCluster", "SortOrderInClan");
    push @headers, "ClanColor" if $colorUtil;
    print CLUSTER join("\t", @headers), "\n";

    foreach my $clusterNum (sort { $a <=> $b } keys %clusterData) {
        foreach my $line (@{$clusterData{$clusterNum}}) {
            my $id = "SSN$clusterNum-CL" . $line->[1] . "-FAM" . $line->[2] . "-" . $line->[3];
            my $clusterId = "SSN" . $clusterNum;
            my $clanId = "CL" . $line->[1];
            my $famId = "FAM" . $line->[2];
            my $sortOrder = $line->[3];
            my $uniqueId = join("-", $clusterId, $clanId, $famId, $sortOrder);
            my @values = ($uniqueId, $clusterId, $line->[0], $clanId, $famId, $sortOrder);
            push @values, $colorUtil->getColorForPfam("$clusterId$clanId") if $colorUtil;
            print CLUSTER join("\t", @values), "\n";
        }
    }
    
    close CLUSTER;
}

sub sortFn {
    my $sizer = $a->[3]; # reference to a hash that contains cluster size
    my $sortResult = $sizer->{$b->[1]} <=> $sizer->{$a->[1]}; # sort by clan size first
    
    if ($sortResult == 0) {
        $sortResult = $a->[1] <=> $b->[1]; # then sort by clan number
        if (not $sortResult) {
            $sortResult = $a->[2] <=> $b->[2]; # then sort by family number
        }
    }

    $sortResult;
}


sub getColors {
    my $colorUtil = 0;
    # If a config file was specified, then connect to the database and retrieve the available colors.
    if (defined $configFile and -f $configFile) {
        my $db = new EFI::Database(config_file_path => $configFile);
        my $colorDbh = $db->getHandle();
        $colorUtil = new EFI::GNN::ColorUtil(dbh => $colorDbh);
        $colorDbh->disconnect();
    }
    return $colorUtil;
}




package DummyColor;

sub new {
    my $class = shift;

    my $self = {};
    bless $self, $class;

    return $self;
}


sub getColorForPfam {
    my $self = shift;
    return "";
}


