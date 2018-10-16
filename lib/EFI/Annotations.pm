
package EFI::Annotations;

use strict;
use constant UNIREF_ONLY => 1;

# Use these rather than the ones in EFI::Config
use constant FIELD_SEQ_SRC_KEY => "Sequence_Source";
use constant FIELD_SEQ_SRC_VALUE_BOTH => "FAMILY+USER";
use constant FIELD_SEQ_SRC_VALUE_FASTA => "USER";
use constant FIELD_SEQ_SRC_VALUE_FAMILY => "FAMILY";
use constant FIELD_SEQ_SRC_VALUE_INPUT => "INPUT";
use constant FIELD_SEQ_SRC_VALUE_BLASTHIT => "BLASTHIT";
use constant FIELD_SEQ_SRC_VALUE_BLASTHIT_FAMILY => "FAMILY+BLASTHIT";
use constant FIELD_SEQ_KEY => "Sequence";
use constant FIELD_ID_ACC => "ACC";

our $Version = 2;


sub new {
    my ($class, %args) = @_;

    my $self = {};
    bless($self, $class);
    
    return $self;
}


sub build_taxid_query_string {
    my $taxid = shift;
    return build_query_string_base("Taxonomy_ID", $taxid);
}


sub build_query_string {
    my $accession = shift;
    my $unirefVersion = shift;
    return build_query_string_base("accession", $accession, $unirefVersion);
}


sub build_query_string_base {
    my $column = shift;
    my $id = shift;

    my @ids = ($id);
    if (ref $id eq "ARRAY") {
        @ids = @$id;
    }

    my $idQuoted = "";
    if (scalar @ids > 1) {
        $idQuoted = "in (" . join(",", map { "'$_'" } @ids) . ")";
    } else {
        $idQuoted = "= '" . $ids[0] . "'";
    }

    my $sql = "";
    if ($Version == 1) {
        $sql = "select * from annotations where $column $idQuoted";
    } else {
        $sql = "select * from annotations as A left join taxonomy as T on A.Taxonomy_ID = T.Taxonomy_ID where A.$column $idQuoted";
    }

    return $sql;
}


sub build_uniref_id_query_string {
    my $seed = shift;
    my $unirefVersion = shift;

    my $sql = "select accession as ID from uniref where uniref${unirefVersion}_seed = '$seed'";

    return $sql;
}


sub build_id_mapping_query_string {
    my $accession = shift;
    my $sql = "select foreign_id_type, foreign_id from idmapping where uniprot_id = '$accession'";
    return $sql;
}

my $AnnoRowSep = "^";

sub build_annotations {
    my $accession = shift;
    my $row = shift;
    my $ncbiIds = shift;

    if (ref $accession eq "HASH" and not defined $ncbiIds) {
        $ncbiIds = $row;
        $row = $accession;
        $accession = $row->{accession};
    }

    my @rows = ($row);
    if (ref $row eq "ARRAY") {
        @rows = @$row;
    }

    my @statusValues;
    foreach my $row (@rows) {
        my $status = "TrEMBL";
        $status = "SwissProt" if lc $row->{STATUS} eq "reviewed";
        push @statusValues, $status;
    }
    my $status = join($AnnoRowSep, @statusValues);

    my $tab = $accession .
        "\n\tSTATUS\t" . $status . 
        "\n\tSequence_Length\t" . merge_anno_rows(\@rows, "Sequence_Length") . 
        "\n\tTaxonomy_ID\t" . merge_anno_rows(\@rows, "Taxonomy_ID") . 
        "\n\tP01_gDNA\t" . merge_anno_rows(\@rows, "GDNA") . 
        "\n\tDescription\t" . merge_anno_rows(\@rows, "Description") . 
        "\n\tSwissprot_Description\t" . merge_anno_rows(\@rows, "SwissProt_Description") . 
        "\n\tOrganism\t" . merge_anno_rows(\@rows, "Organism") . 
        "\n\tGN\t" . merge_anno_rows(\@rows, "GN") . 
        "\n\tPFAM\t" . merge_anno_rows(\@rows, "PFAM") . 
        "\n\tPDB\t" . merge_anno_rows(\@rows, "pdb") . 
        "\n\tIPRO\t" . merge_anno_rows(\@rows, "IPRO") . 
        "\n\tGO\t" . merge_anno_rows(\@rows, "GO") .
        "\n\tKEGG\t" . merge_anno_rows(\@rows, "KEGG") .
        "\n\tSTRING\t" . merge_anno_rows(\@rows, "STRING") .
        "\n\tBRENDA\t" . merge_anno_rows(\@rows, "BRENDA") .
        "\n\tPATRIC\t" . merge_anno_rows(\@rows, "PATRIC") .
        "\n\tHMP_Body_Site\t" . merge_anno_rows(\@rows, "HMP_Body_Site") .
        "\n\tHMP_Oxygen\t" . merge_anno_rows(\@rows, "HMP_Oxygen") .
        "\n\tEC\t" . merge_anno_rows(\@rows, "EC") .
        "\n\tSuperkingdom\t" . merge_anno_rows(\@rows, "Domain");
    $tab .= "\n\tKingdom\t" . merge_anno_rows(\@rows, "Kingdom") if $Version > 1;
    $tab .=
        "\n\tPhylum\t" . merge_anno_rows(\@rows, "Phylum") .
        "\n\tClass\t" . merge_anno_rows(\@rows, "Class") .
        "\n\tOrder\t" . merge_anno_rows(\@rows, "TaxOrder") .
        "\n\tFamily\t" . merge_anno_rows(\@rows, "Family") .
        "\n\tGenus\t" . merge_anno_rows(\@rows, "Genus") .
        "\n\tSpecies\t" . merge_anno_rows(\@rows, "Species") .
        "\n\tCAZY\t" . merge_anno_rows(\@rows, "Cazy");
    $tab .= "\n\tNCBI_IDs\t" . join(",", @$ncbiIds) if ($ncbiIds);
#    $tab .= "\n\tUniRef50\t" . $row->{"UniRef50_Cluster"} if $row->{"UniRef50_Cluster"};
#    $tab .= "\n\tUniRef90\t" . $row->{"UniRef90_Cluster"} if $row->{"UniRef90_Cluster"};
    $tab .= "\n";

    return $tab;
}

sub merge_anno_rows {
    my $rows = shift;
    my $field = shift;

    my $value = join($AnnoRowSep, map { $_->{$field} } @$rows);
    return $value;
}


sub get_annotation_data {
    my %annoData;

    my $idx = 0;

    $annoData{"ACC"}                    = {order => $idx++, display => "List of IDs in Rep Node"};
    $annoData{"Cluster Size"}           = {order => $idx++, display => "Number of IDs in Rep Node"};
    $annoData{"Sequence_Source"}        = {order => $idx++, display => "Sequence Source"};
    $annoData{"Query_IDs"}              = {order => $idx++, display => "Query IDs"};
    $annoData{"Other_IDs"}              = {order => $idx++, display => "Other IDs"};
    $annoData{"Organism"}               = {order => $idx++, display => "Organism"};
    $annoData{"Taxonomy_ID"}            = {order => $idx++, display => "Taxonomy ID"};
    $annoData{"STATUS"}                 = {order => $idx++, display => "UniProt Annotation Status"};
    $annoData{"Description"}            = {order => $idx++, display => "Description"};
    $annoData{"Swissprot_Description"}  = {order => $idx++, display => "Swissprot Description"};
    $annoData{"Sequence_Length"}        = {order => $idx++, display => "Sequence Length"};
    $annoData{"GN"}                     = {order => $idx++, display => "Gene Name"};
    $annoData{"NCBI_IDs"}               = {order => $idx++, display => "NCBI IDs"};
    $annoData{"Superkingdom"}           = {order => $idx++, display => "Superkingdom"};
    $annoData{"Kingdom"}                = {order => $idx++, display => "Kingdom"};
    $annoData{"Phylum"}                 = {order => $idx++, display => "Phylum"};
    $annoData{"Class"}                  = {order => $idx++, display => "Class"};
    $annoData{"Order"}                  = {order => $idx++, display => "Order"};
    $annoData{"Family"}                 = {order => $idx++, display => "Family"};
    $annoData{"Genus"}                  = {order => $idx++, display => "Genus"};
    $annoData{"Species"}                = {order => $idx++, display => "Species"};
    $annoData{"EC"}                     = {order => $idx++, display => "EC"};
    $annoData{"PFAM"}                   = {order => $idx++, display => "PFAM"};
    $annoData{"PDB"}                    = {order => $idx++, display => "PDB"};
    $annoData{"IPRO"}                   = {order => $idx++, display => "IPRO"};
    $annoData{"BRENDA"}                 = {order => $idx++, display => "BRENDA ID"};
    $annoData{"CAZY"}                   = {order => $idx++, display => "CAZY Name"};
    $annoData{"GO"}                     = {order => $idx++, display => "GO Term"};
    $annoData{"KEGG"}                   = {order => $idx++, display => "KEGG ID"};
    $annoData{"PATRIC"}                 = {order => $idx++, display => "PATRIC ID"};
    $annoData{"STRING"}                 = {order => $idx++, display => "STRING ID"};
    $annoData{"HMP_Body_Site"}          = {order => $idx++, display => "HMP Body Site"};
    $annoData{"HMP_Oxygen"}             = {order => $idx++, display => "HMP Oxygen"};
    $annoData{"P01_gDNA"}               = {order => $idx++, display => "P01 gDNA"};
    $annoData{"UniRef50_IDs"}           = {order => $idx++, display => "UniRef50 Cluster IDs"};
    $annoData{"UniRef50_Cluster_Size"}  = {order => $idx++, display => "UniRef50 Cluster Size"};
    $annoData{"UniRef90_IDs"}           = {order => $idx++, display => "UniRef90 Cluster IDs"};
    $annoData{"UniRef90_Cluster_Size"}  = {order => $idx++, display => "UniRef90 Cluster Size"};
    $annoData{"UniRef100_IDs"}          = {order => $idx++, display => "UniRef100 Cluster IDs"};
    $annoData{"UniRef100_Cluster_Size"} = {order => $idx++, display => "UniRef100 Cluster Size"};
    $annoData{"ACC_CDHIT"}              = {order => $idx++, display => "CD-HIT IDs"};
    $annoData{"ACC_CDHIT_COUNT"}        = {order => $idx++, display => "CD-HIT Cluster Size"};
    $annoData{FIELD_SEQ_KEY}            = {order => $idx++, display => "Sequence"};

    return \%annoData;
}

sub sort_annotations {
    my ($annoData, @metas) = @_;

    map {
        if (not exists $annoData->{$_}) {
            $annoData->{$_}->{order} = 999;
            $annoData->{$_}->{display} = $_;
        }
    } @metas;

    @metas = sort {
        if (exists $annoData->{$a} and exists $annoData->{$b}) {
            return $annoData->{$a}->{order} <=> $annoData->{$b}->{order};
        } else {
            return 1;
        }
    } @metas;

    return @metas;
}

# Returns true if the attribute should be a list in the xgmml.
sub is_list_attribute {
    my $self = shift;
    my $attr = shift;

    $self->{anno} = get_annotation_data() if not exists $self->{anno};

    return (
        $attr eq "IPRO"             or $attr eq $self->{anno}->{"IPRO"}->{display}          or 
        $attr eq "GI"               or $attr eq $self->{anno}->{"GI"}->{display}            or 
        $attr eq "PDB"              or $attr eq $self->{anno}->{"PDB"}->{display}           or
        $attr eq "PFAM"             or $attr eq $self->{anno}->{"PFAM"}->{display}          or 
        $attr eq "GO"               or $attr eq $self->{anno}->{"GO"}->{display}            or 
        $attr eq "HMP_Body_Site"    or $attr eq $self->{anno}->{"HMP_Body_Site"}->{display} or
        $attr eq "CAZY"             or $attr eq $self->{anno}->{"CAZY"}->{display}          or 
        $attr eq "Query_IDs"        or $attr eq $self->{anno}->{"Query_IDs"}->{display}     or 
        $attr eq "Other_IDs"        or $attr eq $self->{anno}->{"Other_IDs"}->{display}     or
        $attr eq "Description"      or $attr eq $self->{anno}->{"Description"}->{display}   or 
        $attr eq "NCBI_IDs"         or $attr eq $self->{anno}->{"NCBI_IDs"}->{display}      or 
        $attr eq "UniRef50_IDs"     or $attr eq $self->{anno}->{"UniRef50_IDs"}->{display}  or
        $attr eq "UniRef90_IDs"     or $attr eq $self->{anno}->{"UniRef90_IDs"}->{display}  or 
        $attr eq "ACC_CDHIT"        or $attr eq $self->{anno}->{"ACC_CDHIT"}->{display}
    );
}

sub get_attribute_type {
    my $attr = shift;

    if ($attr eq "Sequence_Length" or $attr eq "UniRef50_Cluster_Size" or $attr eq "UniRef90_Cluster_Size" or
        $attr eq "UniRef100_Cluster_Size" or $attr eq "ACC_CDHIT_COUNT" or $attr eq "Cluster Size")
    {
        return "integer";
    } else {
        return "string";
    }
}

sub is_expandable_attr {
    my $self = shift;
    my $attr = shift;
    my $flag = shift;

    $flag = 0 if not defined $flag;
    $flag = $flag == flag_uniref_only();

    $self->{anno} = get_annotation_data() if not exists $self->{anno};

    my $result = 0;
    if (not $flag) {
        $result = (
            $attr eq FIELD_ID_ACC       or $attr eq $self->{anno}->{"ACC"}->{display}               or 
            $attr eq "ACC_CDHIT"        or $attr eq $self->{anno}->{"ACC_CDHIT"}->{display}
        );
    }
    $result = ($result or (
        $attr eq "UniRef50_IDs"     or $attr eq $self->{anno}->{"UniRef50_IDs"}->{display}      or 
        $attr eq "UniRef90_IDs"     or $attr eq $self->{anno}->{"UniRef90_IDs"}->{display}      or 
        $attr eq "UniRef100_IDs"    or $attr eq $self->{anno}->{"UniRef100_IDs"}->{display}     
    ));
    return $result;
}

sub flag_uniref_only {
    return UNIREF_ONLY;
}

1;

