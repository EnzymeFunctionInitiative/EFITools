#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin . "/../../lib";

use Getopt::Long;

use EFI::CGFP::Util qw(getAbundanceData expandMetanodeIds getClusterMap getMetagenomeInfo);
use EFI::Annotations;
use EFI::SSN::Parser;


my ($ssnIn, $ssnOut, $markerFile, $proteinFile, $clusterFile, $clusterMapFile, $isQuantify, $dbFiles, $metagenomeIdList, $cdhitFile);
my ($isMergedResults);
my $result = GetOptions(
    "ssn-in=s"              => \$ssnIn,
    "ssn-out=s"             => \$ssnOut,
    "marker-file=s"         => \$markerFile,
    "protein-file=s"        => \$proteinFile,
    "cluster-file=s"        => \$clusterFile,
    "cluster-map=s"         => \$clusterMapFile,
    "merge-ssn|quantify"    => \$isQuantify,
    "merged-results"        => \$isMergedResults,
    "metagenome-db=s"       => \$dbFiles,
    "metagenome-ids=s"      => \$metagenomeIdList,
    "cdhit-file=s"          => \$cdhitFile,
);

my $usage = <<USAGE;
$0 -ssn-in path_to_input_ssn -ssn-out path_to_output_ssn
    [-marker-file path_to_shortbred_marker_file -cluster-map path_to_cluster-protein_map_file]  <-- for identify step
    [-protein-file path_to_protein_abundance_file -cluster-file path_to_cluster_abundance_file -quantify] <-- for quantify step
USAGE

die "$usage\ninvalid --ssn-in" if not $ssnIn or not -f $ssnIn;
die "$usage\ninvalid --ssn-out" if not $ssnOut;
die "$usage\nnot isQuantify and not marker file" if not $isQuantify and (not $markerFile or not -f $markerFile);
die "$usage\nis quantify and missing prot or cluster file" if defined $isQuantify and (not $proteinFile or not -f $proteinFile or not $clusterFile or not -f $clusterFile);

$isQuantify = 0 if not defined $isQuantify;
$isMergedResults = 0 if not defined $isMergedResults;

my $efiAnnoUtil = new EFI::Annotations;

my $markerData = {};
my $clusterMap = {};
my $abData = {};

my @metagenomeIds;
my $metagenomeInfo = {};
my $metaMeta = {};
if (defined $metagenomeIdList and $metagenomeIdList and defined $dbFiles and $dbFiles) {
    @metagenomeIds = split(m/,/, $metagenomeIdList);
    ($metagenomeInfo, $metaMeta) = getMetagenomeInfo($dbFiles, @metagenomeIds);
}

my $cdhitInfo = {};
if (defined $cdhitFile and -f $cdhitFile) {
    $cdhitInfo = getCdHitClusters($cdhitFile);
}



# Only get marker data and cluster map if we're generating the data from the initial step
if (not $isQuantify) {
    $markerData = getMarkerData($markerFile);
    $clusterMap = getClusterMap($clusterMapFile);
} else {
    $abData = getAbundanceData($proteinFile, $clusterFile, 1, $isMergedResults); # cleanIds = yes, don't use merged data (cluster num in separate column) = yes
}




my $ssn = openSsn($ssnIn);
$ssn->parse;

if ($isQuantify) {
    $ssn->registerHandler(NODE_WRITER, \&writeQuantifyResults);
} else {
    $ssn->registerHandler(NODE_WRITER, \&writeMarkerResults);
}

$ssn->write($ssnOut);






sub getMarkerData {
    my $file = shift;

    my $markerData = {};

    open FH, $file or die "Unable to open marker file $file: $!";

    while (<FH>) {
        chomp;
        if (m/^>/) {
            my $header = $_;
            (my $type = $header) =~ s/^.*_([TJQ]M)[0-9]*_.*$/$1/;
            $header =~ s/^>(tr|sp)\|/>/;
            if ($header =~ m/^>([A-Z0-9z]{6,})/) {
                my $id = $1;
                $markerData->{$id} = {count => 0, type => $type} if not exists $markerData->{$id};
                $markerData->{$id}->{count}++;
            }
        }
    }

    close FH;

    return $markerData;
}


sub writeQuantifyResults {
    my $nodeId = shift;
    my $childNodeIds = shift;
    my $fieldWriter = shift;
    my $listWriter = shift;

    my $mgList = $abData->{metagenomes};

    my (@mg, @vals, @markerIds, @seedIds, @mgMarker, @mgMarkerVals, @seedMgMarker);
    foreach my $id ($nodeId, @$childNodeIds) {
        # Check if there are any results for the current node (seed or not)
        if (exists $abData->{proteins}->{$id}) {
            # This node is a seed sequence
            if (exists $cdhitInfo->{seeds}->{$id}) {
                my ($mgLocal, $valsLocal) = getQuantifyVals($id);
                push @mg, @$mgLocal;
                push @vals, @$valsLocal;
                push @markerIds, $id;
                push @mgMarker, map { "$id - $_" } @$mgLocal;
                push @mgMarkerVals, map { "$id - $_" } @$valsLocal;
            }
            elsif (exists $cdhitInfo->{members}->{$id}) {
                print STDERR "WARNING: There were some results for a non-seed sequence: $id\n";
            }
        }

        # Check if there are any results for the "parent" (seed) sequence.
        if (exists $cdhitInfo->{members}->{$id} and exists $abData->{proteins}->{$cdhitInfo->{members}->{$id}}) {
            my $seed = $cdhitInfo->{members}->{$id};
            my ($mgLocal, $valsLocal) = getQuantifyVals($seed);
            push @seedMgMarker, map { "$seed - $_" } @$mgLocal;
        }
    }

    if (scalar @mgMarker) {
        &$listWriter("Metagenomes Identified by Markers", "string", \@mgMarker);
    }

    if (scalar @seedMgMarker) {
        &$listWriter("Metagenomes Identified by CD-HIT Family", "string", \@seedMgMarker);
    }
}


sub getQuantifyVals {
    my $id = shift;

    my $mgList = $abData->{metagenomes};

    my (@mg, @vals);
    for (my $i = 0; $i <= $#$mgList; $i++) {
        my $mgId = $mgList->[$i];
        my $hasVal = exists($abData->{proteins}->{$id}->{$mgId}) ? length($abData->{proteins}->{$id}->{$mgId}) : 0;
        my $val = $abData->{proteins}->{$id}->{$mgId};
        $hasVal = $hasVal ? $val > 0 : 0;
        if ($hasVal) {
            my $mgName = $mgId;
            $mgName = $metagenomeInfo->{$mgId}->{bodysite} if exists $metagenomeInfo->{$mgId}->{bodysite} and $metagenomeInfo->{$mgId}->{bodysite};
            $mgName .= ", " . $metagenomeInfo->{$mgId}->{gender} if exists $metagenomeInfo->{$mgId}->{gender} and $metagenomeInfo->{$mgId}->{gender};
            push @mg, $mgName;
            push @vals, $abData->{proteins}->{$id}->{$mgId};
        }
    }

    return(\@mg, \@vals);
}


sub writeMarkerResults {
    my $nodeId = shift;
    my $childNodeIds = shift;
    my $fieldWriter = shift;
    my $listWriter = shift;

    my (@markerTypeNames, @markerIsTrue, @markerCount, @markerIds, @markerClusters, @markerSingles,
        @contribsToMarker, %seedsInNode, %seedsOfNode, @idsWithMarkers);
    foreach my $id (@{$childNodeIds}, $nodeId) {
        # $cdhitInfo contains the mapping of IDs of members of cd-hit clusters to cd-hit seed sequence
        #   (this is not a seed seq)     (seed seq has marker data)
        if (exists $cdhitInfo->{members}->{$id}) {
            my $seedId = $cdhitInfo->{members}->{$id};
            push @contribsToMarker, $seedId;
        }
        if (exists $cdhitInfo->{seeds}->{$id}) {
            $seedsInNode{$id} = 1;
        }
        if (exists $cdhitInfo->{members}->{$id}) {
            my $seedId = $cdhitInfo->{members}->{$id};
            $seedsOfNode{$seedId} = 1; #"$id =seed $seedId";
        }

        next if not exists $markerData->{$id};

        push @idsWithMarkers, $id;

        my $markerType = $markerData->{$id}->{type};
        my $markerTypeName = $markerType eq "TM" ? "True" : $markerType eq "JM" ? "Junction" : $markerType eq "QM" ? "Quasi" : "";
        my $isTrue = $markerType eq "TM";
        my $mCount = $markerData->{$id}->{count};
        push @markerTypeNames, $markerTypeName;
        push @markerIsTrue, $isTrue;
        push @markerCount, $mCount;
        push @markerIds, $id;
        my $cluster = exists $clusterMap->{$id} ? $clusterMap->{$id} : "N/A";
        if ($cluster =~ m/^S/) {
            $cluster =~ s/^S//;
            push @markerSingles, $cluster;
        } else {
            push @markerClusters, $cluster;
        }
    }

    my @seedsInNode = keys %seedsInNode;
    if (scalar @seedsInNode) {
        &$listWriter("Seed Sequence(s)", "string", \@seedsInNode);
    }

    my @seedsOfNode = keys %seedsOfNode;
    if (scalar @seedsOfNode) {
        &$listWriter("Seed Sequence Cluster(s)", "string", \@seedsOfNode);
    }

    if (scalar @idsWithMarkers) {
        &$listWriter("Marker Types", "string", \@markerTypeNames);
        &$listWriter("Number of Markers", "integer", \@markerCount);
    }
}


sub getCdHitClusters {
    my $file = shift;

    my $info = {seeds => {}, members => {}};

    open FILE, $file or warn "Unable to read CD-HIT results table $file: $!";

    while (<FILE>) {
        chomp;
        my ($cluster, $seed, $id) = split(m/\t/);
        $info->{members}->{$id} = $seed;
        push(@{$info->{seeds}->{$seed}}, $id);
    }

    close FILE;

    return $info;
}



