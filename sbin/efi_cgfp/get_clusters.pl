#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin . "/../../lib";

use XML::LibXML::Reader;
use Getopt::Long;

use EFI::Annotations;
use EFI::SSN::Parser;

my ($ssn, $accFile, $clusterFile, $useDefaultClusterNumbering, $seqFile, $minSeqLen, $maxSeqLen);

my $result = GetOptions(
    "ssn=s"             => \$ssn,
    "accession-file=s"  => \$accFile,
    "cluster-file=s"    => \$clusterFile,
    "default-numbering" => \$useDefaultClusterNumbering,
    "sequence-file=s"   => \$seqFile,
    "min-seq-len=i"     => \$minSeqLen,
    "max-seq-len=i"     => \$maxSeqLen,
);


my $usage =
"$0 -ssn=path_to_ssn -accession-file=output_accession_list -cluster-file=output_cluster_list";

die $usage if not defined $ssn or not -f $ssn or not defined $accFile or not $accFile or not defined $clusterFile or not $clusterFile;

$useDefaultClusterNumbering = 0 if not defined $useDefaultClusterNumbering;
$useDefaultClusterNumbering = 1 if defined $useDefaultClusterNumbering;
$seqFile = "" if not defined $seqFile;
$minSeqLen = 0 if not defined $minSeqLen;
$maxSeqLen = 1000000 if not defined $maxSeqLen;


my $efiAnnoUtil = new EFI::Annotations;

#my $reader = XML::LibXML::Reader->new(location => $ssn);

#my ($name, $nodes, $edges, $degrees) = getNodesAndEdges($reader);
my ($network, $nodeIds, $clusterNumbers) = getNodesAndEdgesAndSequences3($ssn, $seqFile);
my ($clusters, $constellations) = getClusters($network, $nodeIds);


# Sort by cluster size
my @clusterIds = sort {
        my $cmp = scalar(@{$clusters->{$b}}) <=> scalar(@{$clusters->{$a}});
        return $cmp if $cmp;
        return $a <=> $b;
    } keys %$clusters;

open CLUSTER, "> $clusterFile" or die "Unable to write to cluster file $clusterFile: $!";
open ACCESSION, "> $accFile" or die "Unable to write to accession file $accFile: $!";

my $clusterCount = 0;
my $singleCount = 0;
my @singles;

foreach my $clusterId (@clusterIds) {
    my @ids = sort @{$clusters->{$clusterId}};
    my $isSingle = scalar @ids == 1;
    if ($isSingle) {
        $singleCount++;
    } else {
        $clusterCount++;
    }
    foreach my $id (@ids) {
        my $clusterNumber = $clusterCount;
        if (exists $clusterNumbers->{$id}) {
            $clusterNumber = $clusterNumbers->{$id};
        }
        print CLUSTER join("\t", $clusterNumber, $id), "\n";
        print ACCESSION "$id\n";
    }
}

close ACCESSION;
close CLUSTER;
















sub getNodesAndEdgesAndSequences3 {
    my $ssnFile = shift;
    my $seqFile = shift;

    my $ssn = openSsn($ssnFile);
    die "Unable to open SSN $ssnFile for reading: $!" if not $ssn;

    if ($seqFile) {
        open SEQ, ">$seqFile";
    }

    my @network;
    my @nodeIds;
    my $clusterNumbers = {};

    my $metaHandler = sub {};
    my $nodeHandler = sub {
        my ($xmlNode, $params) = @_;
        my $nodeId = $params->{node_id};
        saveSequence($xmlNode, $nodeId, \*SEQ) if $seqFile;
        my @ids = (@{$params->{node_ids}}, $nodeId);
        if ($params->{cluster_num}) {
            foreach my $id (@ids) {
                $clusterNumbers->{$id} = $params->{cluster_num} if not exists $clusterNumbers->{$id};
            }
        }
        push @nodeIds, @ids;
    };
    my $edgeHandler = sub {
        my $xmlNode = shift;
        
        my $label = $xmlNode->getAttribute("label");
        my ($source, $target);
        if (defined $label) {
            ($source, $target) = split(m/,/, $label);
        }
        if (not defined $source or not $source or not defined $target or not $target) {
            $source = $xmlNode->getAttribute("source");
            $target = $xmlNode->getAttribute("target");
        }

        die "No source $xmlNode" if not $source;
        die "No target $xmlNode" if not $target;

        $source =~ s/:\d+:\d+$//;
        $target =~ s/:\d+:\d+$//;

        push @network, {source => $source, target => $target};
    };

    $ssn->registerHandler(METADATA_READER, $metaHandler);
    $ssn->registerHandler(NODE_READER, $nodeHandler);
    $ssn->registerHandler(EDGE_READER, $edgeHandler);
    $ssn->registerAnnotationUtil($efiAnnoUtil);

    $ssn->parse(OPT_GET_CLUSTER_NUMBER | OPT_EXPAND_METANODE_IDS);

    if ($seqFile) {
        close SEQ;
    }
    
    return \@network, \@nodeIds, $clusterNumbers;
}


sub saveSequence {
    my $xmlNode = shift;
    my $nodeId = shift;
    my $fh = shift;

    my @seqs;
    my @ids;

    my @annotations = $xmlNode->findnodes('./*');
    foreach my $annotation (@annotations) {
        my $attrName = $annotation->getAttribute('name');
        my $attrType = $annotation->getAttribute('type');
        if ($efiAnnoUtil->is_expandable_attr($attrName, EFI::Annotations::flag_repnode_only())) {
            my @accessionlists = $annotation->findnodes('./*');
            foreach my $accessionlist (@accessionlists) {
                my $attrAcc = $accessionlist->getAttribute('value');
                push @ids, $attrAcc if $attrAcc =~ m/^z/;
            }
        }
        if ($attrName eq EFI::Annotations::FIELD_SEQ_KEY) {
            if ($attrType eq "list") {
                my @seqAttrList = $annotation->findnodes('./*');
                foreach my $seqAttr (@seqAttrList) {
                    my $seq = $seqAttr->getAttribute('value');
                    push @seqs, $seq;
                }
            } else {
                my $seq = $annotation->getAttribute('value');
                $seq =~ s/\s//gs;
                push @seqs, $seq;
            }
        }
    }

    if (not scalar @ids and scalar @seqs) {
        push @ids, $nodeId;
    }

    for (my $i = 0; $i <= $#ids; $i++) {
        if ($seqs[$i] and length $seqs[$i] >= $minSeqLen and length $seqs[$i] <= $maxSeqLen) {
            $fh->print(">" . $ids[$i] . "\n" . $seqs[$i] . "\n\n");
        }
    }
}


sub getClusters {
    my $edges = shift;
    my $nodeIds = shift;

    my %con;
    my %super;

    my $clusterId = 1;

    foreach my $edge (@$edges) {
        my $source = $edge->{source};
        my $target = $edge->{target};

        if (exists $con{$source}) {
            if (exists $con{$target}) {
                next if ($con{$target} eq $con{$source});
                push @{$super{$con{$source}}}, @{$super{$con{$target}}};
                delete $super{$con{$target}};

                my $oldTarget = $con{$target};
                foreach my $node (keys %con) {
                    if ($oldTarget == $con{$node}) {
                        $con{$node} = $con{$source};
                    }
                }
            } else {
                $con{$target} = $con{$source};
                push @{$super{$con{$source}}}, $target;
            }
        } elsif (exists $con{$target}) {
            $con{$source} = $con{$target};
            push @{$super{$con{$target}}}, $source;
        } else {
            $con{$source} = $con{$target} = $clusterId;
            push @{$super{$clusterId}}, $source, $target;
            $clusterId++;
        }
    }

    foreach my $id (@$nodeIds) {
        if (not exists $con{$id}) {
            push @{$super{$clusterId}}, $id;
            $con{$id} = $clusterId;
            $clusterId++;
        }
    }

    return (\%super, \%con);
}




