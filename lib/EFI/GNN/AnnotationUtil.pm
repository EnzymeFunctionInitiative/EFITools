
package EFI::GNN::AnnotationUtil;

use warnings;
use strict;


sub new {
    my ($class, %args) = @_;

    my $self = {};
    bless($self, $class);

    $self->{dbh} = $args{dbh};

    return $self;
}


sub getAnnotations {
    my $self = shift;
    my $accession = shift;
    my $pfams = shift;
    my $ipros = shift;

    my ($orgs, $taxIds, $status, $descs) = $self->getMultipleAnnotations($accession);

    my $organism = $orgs->{$accession};
    my $taxId = $taxIds->{$accession};
    my $annoStatus = $status->{$accession};
    my $desc = $descs->{$accession};

    my $pfamDesc = "";
    my $iproDesc = "";

    if ((defined $pfams and $pfams) or (defined $ipros and $ipros)) {
        my @pfams = $pfams ? (split '-', $pfams) : ();
        my @ipros = $ipros ? (split '-', $ipros) : ();
    
        my $sql = "select family, short_name from family_info where family in ('" . join("','", @pfams, @ipros) . "')";
    
        if (not $self->{dbh}->ping()) {
            warn "Database disconnected at " . scalar localtime;
            $self->{dbh} = $self->{dbh}->clone() or die "Cannot reconnect to database.";
        }
    
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute;
    
        my $rows = $sth->fetchall_arrayref;
    
        $pfamDesc = join(";", map { $_->[1] } grep {$_->[0] =~ m/^PF/} @$rows);
        $iproDesc = join(";", map { $_->[1] } grep {$_->[0] =~ m/^IPR/} @$rows);
    }

    return ($organism, $taxId, $annoStatus, $desc, $pfamDesc, $iproDesc);
}


sub getMultipleAnnotations {
    my $self = shift;
    my $accessions = shift;

    # If it's a single scalar accession convert it to an arrayref.
    if (ref $accessions ne "ARRAY") {
        $accessions = [$accessions];
    }

    my (%organism, %taxId, %annoStatus, %desc);

    foreach my $accession (@$accessions) {
        my $sql = "select Organism,Taxonomy_ID,STATUS,Description from annotations where accession='$accession'";
    
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute;
    
        if (not $self->{dbh}->ping()) {
            warn "Database disconnected at " . scalar localtime;
            $self->{dbh} = $self->{dbh}->clone() or die "Cannot reconnect to database.";
        }

        my ($organism, $taxId, $annoStatus, $desc) = ("", "", "", "");
        if (my $row = $sth->fetchrow_hashref) {
            $organism{$accession} = $row->{Organism};
            $taxId{$accession} = $row->{Taxonomy_ID};
            $annoStatus{$accession} = $row->{STATUS};
            $desc{$accession} = $row->{Description};
        }

        $annoStatus = $annoStatus eq "Reviewed" ? "SwissProt" : "TrEMBL";
    }

    return (\%organism, \%taxId, \%annoStatus, \%desc);
}



1;

