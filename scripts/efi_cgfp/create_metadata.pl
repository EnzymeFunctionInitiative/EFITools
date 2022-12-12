#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../lib";

use Getopt::Long;
use XML::LibXML::Reader;

use EFI::Annotations;
use EFI::CGFP::Util qw(expandMetanodeIds getClusterNumber);
use EFI::SSN::Parser;

my ($ssn, $seqFullFile, $accUniqFile, $clusterFile, $cdhitSbFile, $minSeqLen, $maxSeqLen, $markerFile, $metadataFile);
my ($spClusterFile, $spSingleFile, $clusterSizeFile, $accFullFile);

my $result = GetOptions(
    "ssn=s"                 => \$ssn,
    "sequence-full=s"       => \$seqFullFile, # list of accession IDs after min/max length filters but before uniquing
    "accession-unique=s"    => \$accUniqFile, # list of accession IDs after min/max length filter and CD-HIT 100 uniquing
    "accession-full=s"      => \$accFullFile, # list of accession IDs after min/max length filter and CD-HIT 100 uniquing
    "cluster=s"             => \$clusterFile,
    "cdhit-sb=s"            => \$cdhitSbFile, # output of ShortBRED CD-HIT process (# CD-HIT clusters)
    "min-seq-len=i"         => \$maxSeqLen, 
    "max-seq-len=i"         => \$maxSeqLen, 
    "markers=s"             => \$markerFile,
    "metadata=s"            => \$metadataFile,
    "cluster-size=s"        => \$clusterSizeFile,
    "swissprot-cluster=s"   => \$spClusterFile,
    "swissprot-singleton=s" => \$spSingleFile,
);

print "missing ssn\n" and exit(0) if not $ssn or not -f $ssn;
print "missing accFullFile\n" and exit(0) if not $accFullFile or not -f $accFullFile;
print "missing clusterFile\n" and exit(0) if not $clusterFile or not -f $clusterFile;
print "missing metadataFile\n" and exit(0) if not $metadataFile;
print "missing clusterSizeFile\n" and exit(0) if not $clusterSizeFile;
print "missing spClusterFile\n" and exit(0) if not $spClusterFile;
print "missing spSingleFile\n" and exit(0) if not $spSingleFile;
#Not provided in the case of a child job.
#print "missing cdhitSbFile\n" and exit(0) if not $cdhitSbFile or not -f $cdhitSbFile;
#print "missing markerFile\n" and exit(0) if not $markerFile or not -f $markerFile;
#print "missing accUniqFile\n" and exit(0) if not $accUniqFile or not -f $accUniqFile;
#print "missing seqFullFile\n" and exit(0) if not $seqFullFile or not -f $seqFullFile;


$minSeqLen = "none" if not defined $minSeqLen or not $minSeqLen;
$maxSeqLen = "none" if not defined $maxSeqLen or not $maxSeqLen;




my $metadata = {
    num_metanodes => 0,
    num_ssn_singletons => 0,
    num_ssn_clusters => 0,
};

# These files will not be provided if we're running child job.
if ($markerFile and -f $markerFile and $accUniqFile and -f $accUniqFile and
    $seqFullFile and -f $seqFullFile and $cdhitSbFile and -f $cdhitSbFile)
{
    $metadata->{min_seq_len} = $minSeqLen;
    $metadata->{max_seq_len} = $maxSeqLen;
}

my $efiAnnoUtil = new EFI::Annotations;
#my $reader = XML::LibXML::Reader->new(location => $ssn);
#my ($clusterSize, $spStatus) = countSsnAccessions($reader, $metadata);
my ($clusterSize, $spStatus) = countSsnAccessions2($ssn, $metadata);

my $numRawSeq = `wc -l < $accFullFile`;
chomp $numRawSeq;
$metadata->{num_raw_accessions} = $numRawSeq;

if ($seqFullFile and -f $seqFullFile) {
    my $numFiltSeq = `grep '^>' $seqFullFile | wc -l`;
    chomp $numFiltSeq;
    $metadata->{num_filtered_seq} = $numFiltSeq;
}
if ($accUniqFile and -f $accUniqFile) {
    my $numUniqSeq = `wc -l < $accUniqFile`;
    chomp $numUniqSeq;
    $metadata->{num_unique_seq} = $numUniqSeq;
}
if ($cdhitSbFile and -f $cdhitSbFile) {
    my $numSbClusters = `grep '^>' $cdhitSbFile | wc -l`;
    chomp $numSbClusters;
    $metadata->{num_cdhit_clusters} = $numSbClusters;
}
if ($markerFile and -f $markerFile) {
    my $numMarkers = `grep '^>' $markerFile | wc -l`;
    chomp $numMarkers;
    $metadata->{num_markers} = $numMarkers;
}



open METADATA, ">", $metadataFile or die "Unable to write to metadata file $metadataFile: $!";
foreach my $key (keys %$metadata) {
    print METADATA "$key\t", $metadata->{$key}, "\n";
}
close METADATA;



open CLUSTERSIZE, ">", $clusterSizeFile or die "Unable to write to cluster size file $clusterSizeFile: $!";
print CLUSTERSIZE "Cluster Number\tCluster Sequence Count\n";
#my @clusterIds = sort {$clusterSize->{$b} <=> $clusterSize->{$a}} keys %$clusterSize;
my @clusterIds = sort { $a <=> $b } keys %$clusterSize;
foreach my $id (@clusterIds) {
    print CLUSTERSIZE "$id\t" . $clusterSize->{$id} . "\n";
}
close CLUSTERSIZE;



open SPCLUSTER, ">", $spClusterFile or die "Unable to write to swissprot cluster file $spClusterFile: $!";
open SPSINGLE, ">", $spSingleFile or die "Unable to write to swissprot singleton file $spSingleFile: $!";

print SPCLUSTER join("\t", "Cluster Number", "Protein ID", "SwissProt Annotation"), "\n";
print SPSINGLE join("\t", "Cluster Number", "Protein ID", "SwissProt Annotation"), "\n";

@clusterIds = sort { (my $aa = $a) =~ s/\D//g; (my $bb = $b) =~ s/\D//g; ($aa and $bb) ? $aa <=> $bb : 1 } keys %$spStatus;
foreach my $cid (@clusterIds) {
    my $fh = $cid =~ m/^\d/ ? \*SPCLUSTER : \*SPSINGLE;
    foreach my $id (sort keys %{ $spStatus->{$cid} }) {
        $fh->print(join("\t", $cid, $id, $spStatus->{$cid}->{$id}), "\n");
    }
}

close SPSINGLE;
close SPCLUSTER;









# Gets the node and edge objects, as well as writes any sequences in the XGMML to the sequence file.
sub countSsnAccessions2 {
    my $ssnFile = shift;
    my $metadata = shift;

    my $ssnParser = openSsn($ssnFile);

    my %spStatus;
    my %clusterSize;
    my $singleCount = 0;

    my $nodeHandler = sub {
        my ($xmlNode, $params) = @_;
        my $nodeId = $params->{node_id};

        my $numChildNodes = scalar @{$params->{node_ids}};
        my $clusterId = $params->{cluster_num};
        my $status = EFI::Annotations::get_swissprot_description($xmlNode);
        my $clSizeId = (not $clusterId) ? "Singletons" : $clusterId;
        
        $metadata->{num_metanodes}++;
        $metadata->{is_uniref} = checkUniRef($xmlNode) if not exists $metadata->{is_uniref};
        $singleCount++ if not $clusterId or $clusterId =~ m/^S/;
        $clusterSize{$clusterId} += $numChildNodes if $clusterId and $clusterId =~ m/^\d/;
        $spStatus{$clSizeId}->{$nodeId} = $status if $status;
    };

    $ssnParser->registerHandler(NODE_READER, $nodeHandler);
    $ssnParser->registerAnnotationUtil($efiAnnoUtil);

    $ssnParser->parse(OPT_EXPAND_METANODE_IDS | OPT_GET_CLUSTER_NUMBER);

    my @clusterIds = keys %clusterSize;
    $metadata->{num_ssn_clusters} = scalar @clusterIds;
    $metadata->{num_ssn_singletons} = $singleCount;

    return \%clusterSize, \%spStatus;
}


# Returns the UniRef version (e.g. 50 or 90) that the SSN was generated with, or 0 if UniRef was not used.
sub checkUniRef {
    my $xmlNode = shift;

    my $urVersion = 0;

    my @annotations = $xmlNode->findnodes("./*");
    foreach my $annotation (@annotations) {
        my $attrName = $annotation->getAttribute("name");
        if ($attrName =~ m/UniRef(\d+)/) {
            $urVersion = $1;
            last;
        }
    }

    return $urVersion;
}



