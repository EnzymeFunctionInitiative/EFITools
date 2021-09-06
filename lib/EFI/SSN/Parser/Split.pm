
package EFI::SSN::Parser::Split;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::SSN::Parser);

use Data::Dumper;


sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);

    $self->{node_cluster_map} = {};
    $self->{node_id_map} = {};
    $self->{edge_cluster_map} = {};
    $self->{base_out_name} = $args{base_out_name} // "";
    $self->{out_file} = $args{out_file} // ""; # Single cluster output
    $self->{do_mkdir} = $args{do_mkdir} // 0;

    return $self;
}


sub openSplitSsn {
    my $file = shift;
    my $doMkdir = shift || 0;
    my %args = @_;

    return 0 if not -f $file;

    my $reader = XML::LibXML::Reader->new(location => $file);

    my $self = EFI::SSN::Parser::Split->new(reader => $reader, do_mkdir => $doMkdir, %args);

    return $self;
}


####################################################################################################
# PARSING CODE

sub parseSplit {
    my $self = shift;
    my $flags = shift || 0;

    $flags |= EFI::SSN::Parser::OPT_GET_CLUSTER_NUMBER;
    $flags |= EFI::SSN::Parser::OPT_GET_NODE_ID;
    #$flags ||= EFI::SSN::Parser::OPT_CLUSTER_NUMBER_BY_NODES;
    #return $self->parse((($flags | EFI::SSN::Parser::OPT_GET_CLUSTER_NUMBER) | EFI::SSN::Parser::OPT_GET_NODE_ID));
    return $self->parse($flags);
}
sub postNodeParse {
    my $self = shift;
    my $params = shift;
    my $nodeIdx = shift;
    my $node = shift;
    push @{$self->{node_cluster_map}->{$params->{cluster_num}}}, $nodeIdx;
    $self->{node_id_map}->{$params->{node_real_id}} = $params->{cluster_num};
}
sub postAllEdgesParse {
    my $self = shift;
    my $edges = shift;
    for (my $i = 0; $i <= $#$edges; $i++) {
        my $nodeId = $self->getEdgeStartNodeId($edges->[$i]);
        my $clusterNum = $self->{node_id_map}->{$nodeId} // 0;
        push @{$self->{edge_cluster_map}->{$clusterNum}}, $i if $clusterNum;
    }
}


sub getEdgeStartNodeId {
    my $self = shift;
    my $xmlNode = shift;
    my $nodeId = $xmlNode->getAttribute("source");
    $nodeId =~ s/:\d+:\d+$//; # strip domain info from the ID.
    return $nodeId;
}


sub setClusterNumber {
    my $self = shift;
    my $xmlNode = shift;
    my $number = shift;
    my $useNodeCount = shift || 0;

    # Due to a bug in GNT, multiple instances of the attributes may exist for the same node.  We
    # don't exit the loop below until iterated through all attributes because we want to pick
    # the last entry.
    my $numPrefix = $useNodeCount ? "Node Count" : "Sequence Count";
    my $numAttr = "$numPrefix Cluster Number";

    #print "SET $numAttr " . $xmlNode->getAttribute('label') . "\n";
    #my ($annotation) = $xmlNode->findnodes("./$numAttr");
    #$annotation->setAttribute('value', $number) if $annotation;a

    my @annotations = $xmlNode->findnodes('./*');
    foreach my $annotation (@annotations) {
        my $attrName = $annotation->getAttribute('name');
        if ($attrName eq $numAttr) {
            $annotation->setAttribute('value', $number);
            last;
        }
    }
}


####################################################################################################
# WRITING CODE


sub writeSplit {
    my $self = shift;
    my $dmap = shift;
    #my $dissect = shift || "";

    my $hasDmap = scalar keys %$dmap;
    #my $hasDmap = $dissect ? 1 : 0;
    #my %dmap = map { my ($a, $b) = split(m/:/); my %ret; $ret{$a} = $b ? $b : $a; return %ret; } split(m/,/, $dissect);

    my @clusters = grep { $_ !~ m/\D/ } sort { $a <=> $b } grep m/^\d+$/, keys %{$self->{node_cluster_map}};
    if ($self->{out_file}) {
        my @c = grep { exists $dmap->{$_} } @clusters;
        my $clusterNum = shift @c;
        print "ERROR $self->{out_file} not found\n" if not defined $clusterNum;
        if ($clusterNum) {
            my $output = $self->{out_file};
            $self->{source_cluster_num} = $clusterNum;
            $self->{target_cluster_num} = $dmap->{$clusterNum} // $clusterNum;
            print "WRITE TO $output\n";
            $self->write($output);
        }
    } else {
        foreach my $clusterNum (@clusters) {
            print "SKIPPING $clusterNum because it's not in the dissect map\n" and next if $hasDmap and not exists $dmap->{$clusterNum};

            $self->{source_cluster_num} = $clusterNum;
            $self->{target_cluster_num} = $dmap->{$clusterNum} // $clusterNum; #and $dmap->{$clusterNum} != $clusterNum) ? $dmap->{$clusterNum} : 0;

            my $dir = $self->{base_out_name} . $self->{target_cluster_num}; #($dmap->{$clusterNum} ? $dmap->{$clusterNum} : $clusterNum);
            #print "NOT FOUND $dir\n" and next if not -d $dir;
            mkdir $dir if not -d $dir and $self->{do_mkdir};
            next if not -d $dir;
            my $output = "$dir/ssn.xgmml";
            print "WRITE TO $output\n";
            $self->write($output);
        }
    }
}


sub getNodeList {
    my $self = shift;
    my $useNodeCount = 1;
    my @nodes;
    my $list = $self->{node_cluster_map}->{$self->{source_cluster_num}} // [];
    foreach my $idx (@$list) {
        my $node = $self->{nodes}->[$idx];
        #if ($self->{target_cluster_num}) {
        #    $self->setClusterNumber($node, $self->{target_cluster_num}, $useNodeCount);
        ##} else {
        ##    $self->setClusterNumber($node, $self->{source_cluster_num}, $useNodeCount);
        #}
        push @nodes, $node;
    }
    return \@nodes;
}
sub getEdgeList {
    my $self = shift;
    my @edges;
    my $list = $self->{edge_cluster_map}->{$self->{source_cluster_num}} // [];
    foreach my $idx (@$list) {
        push @edges, $self->{edges}->[$idx];
    }
    return \@edges;
}


1;

