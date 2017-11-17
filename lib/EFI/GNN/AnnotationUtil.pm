
package EFI::GNN::AnnotationUtil;


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
    
    my $sql = "select Organism,Taxonomy_ID,STATUS,Description from annotations where accession='$accession'";

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute;

    my ($organism, $taxId, $annoStatus, $desc) = ("", "", "", "");
    if (my $row = $sth->fetchrow_hashref) {
        $organism = $row->{Organism};
        $taxId = $row->{Taxonomy_ID};
        $annoStatus = $row->{STATUS};
        $desc = $row->{Description};
    }

    my @pfams = split '-', $pfams;

    $sql = "select short_name from pfam_info where pfam in ('" . join("','", @pfams) . "')";

    $sth = $self->{dbh}->prepare($sql);
    $sth->execute;

    my $rows = $sth->fetchall_arrayref;

    my $pfamDesc = join("-", map { $_->[0] } @$rows);

    $annoStatus = $annoStatus eq "Reviewed" ? "SwissProt" : "TrEMBL";

    return ($organism, $taxId, $annoStatus, $desc, $pfamDesc);
}



1;

