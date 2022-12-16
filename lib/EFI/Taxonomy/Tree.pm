
package EFI::Taxonomy::Tree;

use strict;
use warnings;

use JSON;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {data => {}};

    #di"Need an input file" if not $args;
    #d_name "Need an input file";
    #$self->{file} = $args{file};

    bless $self, $class;

    return $self;
}


sub load {
    my $self = shift;
    my $file = shift;

    my $contents = "";
    open my $fh, "<", $file;
    while (<$fh>) {
        $contents .= $_;
    }
    close $fh;

    my $data = JSON::decode_json($contents);

    $self->{data} = $data;

    return 1;
}


sub getSubTree {
    my $self = shift;
    my $nodeId = shift;

    return $self->getSubTreeFind($self->{data}->{data}, $nodeId);
}


sub getSubTreeFind {
    my $self = shift;
    my $tree = shift;
    my $nodeId = shift;

    if (exists $tree->{id} and $tree->{id} eq $nodeId) {
        return $tree;
    } else {
        if ($tree->{children}) {
            foreach my $kid (@{ $tree->{children} }) {
                my $retval = $self->getSubTreeFind($kid, $nodeId);
                if ($retval) {
                    return $retval;
                }
            }
        }
    }

    return undef;
}


sub getIdsFromTree {
    my $self = shift;
    my $tree = shift;
    my $idType = shift // "uniprot";

    if ($idType eq "uniref90") {
        $idType = "sa90";
    } elsif ($idType eq "uniref50") {
        $idType = "sa50";
    } else {
        $idType = "sa";
    }

    my %ids;
    my $action = sub {
        my $node = shift;
        if ($node->{seq}) {
            map { $ids{$_->{$idType}} = 1; } @{ $node->{seq} };
        }
    };

    $self->traverseTree($tree, $action);

    my @ids = sort keys %ids;

    return \@ids;
}


sub traverseTree {
    my $self = shift;
    my $tree = shift;
    my $action = shift;

    &$action($tree);

    if ($tree->{children}) {
        foreach my $kid (@{ $tree->{children} }) {
            $self->traverseTree($kid, $action);
        }
    }

}


1;

