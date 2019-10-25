
package EFI::Annotations;

use strict;
use constant UNIREF_ONLY => 1;
use constant REPNODE_ONLY => 2;

# Use these rather than the ones in EFI::Config
use constant FIELD_SEQ_SRC_KEY => "Sequence_Source";
use constant FIELD_SEQ_SRC_VALUE_BOTH => "FAMILY+USER";
use constant FIELD_SEQ_SRC_VALUE_FASTA => "USER";
use constant FIELD_SEQ_SRC_VALUE_FAMILY => "FAMILY";
use constant FIELD_SEQ_SRC_VALUE_INPUT => "INPUT";
use constant FIELD_SEQ_SRC_VALUE_BLASTHIT => "BLASTHIT";
use constant FIELD_SEQ_SRC_VALUE_BLASTHIT_FAMILY => "FAMILY+BLASTHIT";
use constant FIELD_SEQ_KEY => "Sequence";
use constant FIELD_SEQ_LEN_KEY => "Sequence_Length";
use constant FIELD_SEQ_DOM_LEN_KEY => "Cluster_ID_Domain_Length";
use constant FIELD_UNIREF_CLUSTER_ID_SEQ_LEN_KEY => "Cluster_ID_Sequence_Length";
use constant FIELD_ID_ACC => "ACC";
use constant FIELD_SWISSPROT_DESC => "Swissprot Description";
use constant FIELD_TAXON_ID => "Taxonomy ID";
use constant FIELD_SPECIES => "Species";
use constant FIELD_UNIREF50_IDS => "UniRef50_IDs";
use constant FIELD_UNIREF90_IDS => "UniRef90_IDs";
use constant FIELD_UNIREF100_IDS => "UniRef100_IDs";
use constant FIELD_UNIREF50_CLUSTER_SIZE => "UniRef50_Cluster_Size";
use constant FIELD_UNIREF90_CLUSTER_SIZE => "UniRef90_Cluster_Size";
use constant FIELD_UNIREF100_CLUSTER_SIZE => "UniRef100_Cluster_Size";

our $Version = 2;

use List::MoreUtils qw{uniq} ;


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
    my $extraWhere = shift || "";
    return build_query_string_base("accession", $accession, $extraWhere);
}


sub build_query_string_base {
    my $column = shift;
    my $id = shift;
    my $extraWhere = shift || "";

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
        $sql = <<SQL;
select
    A.*,
    T.*,
    group_concat(distinct P.id) as PFAM2,
    group_concat(I.family_type) as ipro_type,
    group_concat(I.id) as ipro_fam
from annotations as A
left join taxonomy as T on A.Taxonomy_ID = T.Taxonomy_ID
left join PFAM as P on A.accession = P.accession
left join INTERPRO as I on A.accession = I.accession
where A.$column $idQuoted $extraWhere
group by A.accession
SQL
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

# $row is a row (as hashref) from the annotation table in the database.
sub build_annotations {
    my $accession = shift;
    my $row = shift;
    my $ncbiIds = shift;
    my $annoSpec = shift;

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

    my ($iproDom, $iproFam, $iproSup, $iproOther) = parse_interpro(\@rows);

    my $attrFunc = sub {
        return 1 if not $annoSpec;
        return exists $annoSpec->{$_[0]};
    };

    my $tab = $accession .
        "\n\tSTATUS\t" . $status . 
        "\n\tSequence_Length\t" . merge_anno_rows(\@rows, "Sequence_Length");
    $tab .= "\n\tTaxonomy_ID\t" . merge_anno_rows(\@rows, "Taxonomy_ID") if &$attrFunc("Taxonomy_ID"); 
    $tab .= "\n\tP01_gDNA\t" . merge_anno_rows(\@rows, "GDNA") if &$attrFunc("P01_gDNA"); 
    $tab .= "\n\tDescription\t" . merge_anno_rows(\@rows, "Description") if &$attrFunc("Description"); 
    $tab .= "\n\tSwissprot_Description\t" . merge_anno_rows(\@rows, "SwissProt_Description") if &$attrFunc("Swissprot_Description"); 
    $tab .= "\n\tOrganism\t" . merge_anno_rows(\@rows, "Organism") if &$attrFunc("Organism"); 
    $tab .= "\n\tGN\t" . merge_anno_rows(\@rows, "GN") if &$attrFunc("GN"); 
    $tab .= "\n\tPFAM\t" . merge_anno_rows_uniq(\@rows, "PFAM2") if &$attrFunc("PFAM"); 
    $tab .= "\n\tPDB\t" . merge_anno_rows(\@rows, "pdb") if &$attrFunc("PDB"); 
    $tab .= "\n\tIPRO_DOM\t" . join($AnnoRowSep, @$iproDom) if &$attrFunc("IPRO_DOM");
    $tab .= "\n\tIPRO_FAM\t" . join($AnnoRowSep, @$iproFam) if &$attrFunc("IPRO_FAM");
    $tab .= "\n\tIPRO_SUP\t" . join($AnnoRowSep, @$iproSup) if &$attrFunc("IPRO_SUP");
    $tab .= "\n\tIPRO\t" . join($AnnoRowSep, @$iproOther) if &$attrFunc("IPRO");
    $tab .= "\n\tGO\t" . merge_anno_rows(\@rows, "GO") if &$attrFunc("GO");
    $tab .= "\n\tKEGG\t" . merge_anno_rows(\@rows, "KEGG") if &$attrFunc("KEGG");
    $tab .= "\n\tSTRING\t" . merge_anno_rows(\@rows, "STRING") if &$attrFunc("STRING");
    $tab .= "\n\tBRENDA\t" . merge_anno_rows(\@rows, "BRENDA") if &$attrFunc("BRENDA");
    $tab .= "\n\tPATRIC\t" . merge_anno_rows(\@rows, "PATRIC") if &$attrFunc("PATRIC");
    $tab .= "\n\tHMP_Body_Site\t" . merge_anno_rows(\@rows, "HMP_Body_Site") if &$attrFunc("HMP_Body_Site");
    $tab .= "\n\tHMP_Oxygen\t" . merge_anno_rows(\@rows, "HMP_Oxygen") if &$attrFunc("HMP_Oxygen");
    $tab .= "\n\tEC\t" . merge_anno_rows(\@rows, "EC") if &$attrFunc("EC");
    $tab .= "\n\tSuperkingdom\t" . merge_anno_rows(\@rows, "Domain") if &$attrFunc("Superkingdom");
    $tab .= "\n\tKingdom\t" . merge_anno_rows(\@rows, "Kingdom") if $Version > 1 and &$attrFunc("Kingdom");
    $tab .= "\n\tPhylum\t" . merge_anno_rows(\@rows, "Phylum") if &$attrFunc("Phylum");
    $tab .= "\n\tClass\t" . merge_anno_rows(\@rows, "Class") if &$attrFunc("Class");
    $tab .= "\n\tOrder\t" . merge_anno_rows(\@rows, "TaxOrder") if &$attrFunc("Order");
    $tab .= "\n\tFamily\t" . merge_anno_rows(\@rows, "Family") if &$attrFunc("Family");
    $tab .= "\n\tGenus\t" . merge_anno_rows(\@rows, "Genus") if &$attrFunc("Genus");
    $tab .= "\n\tSpecies\t" . merge_anno_rows(\@rows, "Species") if &$attrFunc("Species");
    $tab .= "\n\tCAZY\t" . merge_anno_rows(\@rows, "Cazy") if &$attrFunc("CAZY");
    $tab .= "\n\tNCBI_IDs\t" . join(",", @$ncbiIds) if $ncbiIds and &$attrFunc("NCBI_IDs");
    $tab .= "\n\tFragment\t" . merge_anno_rows(\@rows, "Fragment", {0 => "complete", 1 => "fragment"}) if &$attrFunc("Fragment");
    # UniRef is added elsewhere
    #$tab .= "\n\tUniRef50\t" . $row->{"UniRef50_Cluster"} if $row->{"UniRef50_Cluster"};
    #$tab .= "\n\tUniRef90\t" . $row->{"UniRef90_Cluster"} if $row->{"UniRef90_Cluster"};
    $tab .= "\n";

    return $tab;
}


sub get_uniref_sequence_length {
    my $row = shift;
    return ($row->{accession}, $row->{Sequence_Length});
}


sub parse_interpro {
    my $rows = shift;

    my (@dom, @fam, @sup, @other);
    my %u;

    foreach my $row (@$rows) {
        next if not exists $row->{ipro_fam};

        my @fams = split m/,/, $row->{ipro_fam};
        my @types = split m/,/, $row->{ipro_type};
        #my @parents = split m/,/, $row->{ipro_parent};
        #my @isLeafs = split m/,/, $row->{ipro_is_leaf};
    
        for (my $i = 0; $i < scalar @fams; $i++) {
            next if exists $u{$fams[$i]};
            $u{$fams[$i]} = 1;
            
            my $type = $types[$i];
            my $fam = $fams[$i];
    
            #TODO: remove hardcoded constants here
            push @dom, $fam if $type eq "Domain";
            push @fam, $fam if $type eq "Family";
            push @sup, $fam if $type eq "Homologous_superfamily";
            push @other, $fam if $type ne "Domain" and $type ne "Family" and $type ne "Homologous_superfamily";
        }
    }

    return \@dom, \@fam, \@sup, \@other;
}


sub merge_anno_rows {
    my $rows = shift;
    my $field = shift;
    my $typeSpec = shift || {};

    my $value = join($AnnoRowSep,
        map { 
            exists $typeSpec->{$_->{$field}} ? $typeSpec->{$_->{$field}} : $_->{$field}
        } @$rows);
    return $value;
}


sub merge_anno_rows_uniq {
    my $rows = shift;
    my $field = shift;

    my $value = join($AnnoRowSep,
        map {
            my @parts = split m/,/, $_->{$field};
            return join(",", uniq sort @parts);
        } @$rows);
    return $value;
}


sub get_annotation_data {
    my %annoData;

    my $idx = 0;

    $annoData{"ACC"}                        = {order => $idx++, display => "List of IDs in Rep Node"};
    $annoData{"Cluster Size"}               = {order => $idx++, display => "Number of IDs in Rep Node"};
    $annoData{"Sequence_Source"}            = {order => $idx++, display => "Sequence Source"};
    $annoData{"Query_IDs"}                  = {order => $idx++, display => "Query IDs"};
    $annoData{"Other_IDs"}                  = {order => $idx++, display => "Other IDs"};
    $annoData{"Organism"}                   = {order => $idx++, display => "Organism"};
    $annoData{"Taxonomy_ID"}                = {order => $idx++, display => FIELD_TAXON_ID};
    $annoData{"STATUS"}                     = {order => $idx++, display => "UniProt Annotation Status"};
    $annoData{"Description"}                = {order => $idx++, display => "Description"};
    $annoData{"Swissprot_Description"}      = {order => $idx++, display => FIELD_SWISSPROT_DESC};
    $annoData{"Sequence_Length"}            = {order => $idx++, display => "Sequence Length"};
    $annoData{"Cluster_ID_Domain_Length"}   = {order => $idx++, display => "Cluster ID Domain Length"};
    $annoData{"Cluster_ID_Sequence_Length"} = {order => $idx++, display => "Cluster ID Sequence Length"};
    $annoData{"GN"}                         = {order => $idx++, display => "Gene Name"};
    $annoData{"NCBI_IDs"}                   = {order => $idx++, display => "NCBI IDs"};
    $annoData{"Superkingdom"}               = {order => $idx++, display => "Superkingdom"};
    $annoData{"Kingdom"}                    = {order => $idx++, display => "Kingdom"};
    $annoData{"Phylum"}                     = {order => $idx++, display => "Phylum"};
    $annoData{"Class"}                      = {order => $idx++, display => "Class"};
    $annoData{"Order"}                      = {order => $idx++, display => "Order"};
    $annoData{"Family"}                     = {order => $idx++, display => "Family"};
    $annoData{"Genus"}                      = {order => $idx++, display => "Genus"};
    $annoData{"Species"}                    = {order => $idx++, display => FIELD_SPECIES};
    $annoData{"EC"}                         = {order => $idx++, display => "EC"};
    $annoData{"PFAM"}                       = {order => $idx++, display => "PFAM"};
    $annoData{"PDB"}                        = {order => $idx++, display => "PDB"};
    $annoData{"IPRO_DOM"}                   = {order => $idx++, display => "InterPro (Domain)"};
    $annoData{"IPRO_FAM"}                   = {order => $idx++, display => "InterPro (Family)"};
    $annoData{"IPRO_SUP"}                   = {order => $idx++, display => "InterPro (Homologous Superfamily)"};
    $annoData{"IPRO"}                       = {order => $idx++, display => "InterPro (Other)"};
    $annoData{"BRENDA"}                     = {order => $idx++, display => "BRENDA ID"};
    $annoData{"CAZY"}                       = {order => $idx++, display => "CAZY Name"};
    $annoData{"GO"}                         = {order => $idx++, display => "GO Term"};
    $annoData{"KEGG"}                       = {order => $idx++, display => "KEGG ID"};
    $annoData{"PATRIC"}                     = {order => $idx++, display => "PATRIC ID"};
    $annoData{"STRING"}                     = {order => $idx++, display => "STRING ID"};
    $annoData{"HMP_Body_Site"}              = {order => $idx++, display => "HMP Body Site"};
    $annoData{"HMP_Oxygen"}                 = {order => $idx++, display => "HMP Oxygen"};
    $annoData{"P01_gDNA"}                   = {order => $idx++, display => "P01 gDNA"};
    $annoData{"UniRef50_IDs"}               = {order => $idx++, display => "UniRef50 Cluster IDs"};
    $annoData{"UniRef50_Cluster_Size"}      = {order => $idx++, display => "UniRef50 Cluster Size"};
    $annoData{"UniRef90_IDs"}               = {order => $idx++, display => "UniRef90 Cluster IDs"};
    $annoData{"UniRef90_Cluster_Size"}      = {order => $idx++, display => "UniRef90 Cluster Size"};
    $annoData{"UniRef100_IDs"}              = {order => $idx++, display => "UniRef100 Cluster IDs"};
    $annoData{"UniRef100_Cluster_Size"}     = {order => $idx++, display => "UniRef100 Cluster Size"};
    $annoData{"ACC_CDHIT"}                  = {order => $idx++, display => "CD-HIT IDs"};
    $annoData{"ACC_CDHIT_COUNT"}            = {order => $idx++, display => "CD-HIT Cluster Size"};
    $annoData{"Sequence"}                   = {order => $idx++, display => "Sequence"};
    $annoData{"User_IDs_in_Cluster"}        = {order => $idx++, display => "User IDs in Cluster"};
    $annoData{"Fragment"}                   = {order => $idx++, display => "Sequence Status"};

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
        $attr eq "IPRO"             or $attr eq $self->{anno}->{"IPRO"}->{display}              or 
        $attr eq "GI"               or $attr eq $self->{anno}->{"GI"}->{display}                or 
        $attr eq "PDB"              or $attr eq $self->{anno}->{"PDB"}->{display}               or
        $attr eq "PFAM"             or $attr eq $self->{anno}->{"PFAM"}->{display}              or 
        $attr eq "GO"               or $attr eq $self->{anno}->{"GO"}->{display}                or 
        $attr eq "HMP_Body_Site"    or $attr eq $self->{anno}->{"HMP_Body_Site"}->{display}     or
        $attr eq "CAZY"             or $attr eq $self->{anno}->{"CAZY"}->{display}              or 
        $attr eq "Query_IDs"        or $attr eq $self->{anno}->{"Query_IDs"}->{display}         or 
        $attr eq "Other_IDs"        or $attr eq $self->{anno}->{"Other_IDs"}->{display}         or
        $attr eq "Description"      or $attr eq $self->{anno}->{"Description"}->{display}       or 
        $attr eq "NCBI_IDs"         or $attr eq $self->{anno}->{"NCBI_IDs"}->{display}          or 
        $attr eq FIELD_UNIREF50_IDS or $attr eq $self->{anno}->{"UniRef50_IDs"}->{display}  or
        $attr eq FIELD_UNIREF90_IDS or $attr eq $self->{anno}->{"UniRef90_IDs"}->{display}  or 
        $attr eq "ACC_CDHIT"        or $attr eq $self->{anno}->{"ACC_CDHIT"}->{display} or
        $attr eq "User_IDs_in_Cluster" or $attr eq $self->{anno}->{"User_IDs_in_Cluster"}->{display}
    );
}

sub get_attribute_type {
    my $attr = shift;

    my %intTypes = (
        "Cluster_ID_Sequence_Length" => 1,
        "Sequence_Length" => 1,
        "Cluster_ID_Domain_Length" => 1,
        "UniRef50_Cluster_Size" => 1,
        "UniRef90_Cluster_Size" => 1,
        "UniRef100_Cluster_Size" => 1,
        "ACC_CDHIT_COUNT" => 1,
        "Cluster Size" => 1,
    );

    if (exists $intTypes{$attr}) {
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
    if (not $flag or $flag == flag_repnode_only()) {
        $result = (
            $attr eq FIELD_ID_ACC       or $attr eq $self->{anno}->{"ACC"}->{display}               or 
            $attr eq "ACC_CDHIT"        or $attr eq $self->{anno}->{"ACC_CDHIT"}->{display}
        );
    }
    if (not $flag or $flag == flag_uniref_only()) {
        $result = ($result or (
            $attr eq FIELD_UNIREF50_IDS     or $attr eq $self->{anno}->{"UniRef50_IDs"}->{display}  or 
            $attr eq FIELD_UNIREF90_IDS     or $attr eq $self->{anno}->{"UniRef90_IDs"}->{display}  or 
            $attr eq FIELD_UNIREF100_IDS    or $attr eq $self->{anno}->{"UniRef100_IDs"}->{display}     
        ));
    }
    return $result;
}

sub flag_uniref_only {
    return UNIREF_ONLY;
}

sub flag_repnode_only {
    return REPNODE_ONLY;
}

# Returns the SwissProt description, if any, from an XML node in an SSN.
sub get_swissprot_description {
    my $xmlNode = shift;

    my $spStatus = "";

    my @annotations = $xmlNode->findnodes("./*");
    foreach my $annotation (@annotations) {
        my $attrName = $annotation->getAttribute("name");
        if ($attrName eq FIELD_SWISSPROT_DESC) {
            my $attrType = $annotation->getAttribute("type");

            if ($attrType and $attrType eq "list") {
                $spStatus = get_swissprot_description($annotation);
            } else {
                my $val = $annotation->getAttribute("value");
                $spStatus = $val if $val and length $val > 3; # Skip NA and N/A
            }

            last if $spStatus;
        }
    }

    return $spStatus;
}
1;

