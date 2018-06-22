
package EFI::GNN::Arrows;

use strict;
use DBI;

our $AttributesTable = "attributes";
our $NeighborsTable = "neighbors";

sub new {
    my ($class, %args) = @_;
    
    my $self = {};
    if (exists $args{color_util}) {
        $self->{color_util} = $args{color_util};
    } else {
        $self->{color_util} = new DummyColorUtil;
    }

    return bless($self, $class);
}






sub writeArrowData {
    my $self = shift;
    my $data = shift;
    my $clusterCenters = shift;
    my $file = shift;
    my $metadata = shift;

    unlink $file if -f $file;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$file","","");
    $dbh->{AutoCommit} = 0;

    my %families;

    my @sqlStatements = getCreateAttributeTableSql();
    push @sqlStatements, getCreateNeighborTableSql();
    push @sqlStatements, getCreateFamilyTableSql();
    push @sqlStatements, getCreateDegreeTableSql();
    push @sqlStatements, getCreateMetadataTableSql();
    foreach my $sql (@sqlStatements) {
        $dbh->do($sql);
    }

    my (@cols, @vals);

    if (exists $metadata->{cooccurrence}) {
        push @cols, "cooccurrence";
        push @vals, $metadata->{cooccurrence};
    }
    if (exists $metadata->{neighborhood_size}) {
        push @cols, "neighborhood_size";
        push @vals, $metadata->{neighborhood_size};
    }
    if (exists $metadata->{title}) {
        push @cols, "name";
        push @vals, $metadata->{title};
    }
    if (exists $metadata->{type}) {
        push @cols, "type";
        push @vals, $metadata->{type};
    }
    if (exists $metadata->{sequence}) {
        push @cols, "sequence";
        push @vals, $metadata->{sequence};
    }

    my $sql = "INSERT INTO metadata (" . join(", ", @cols) . ") VALUES(" .
        join(", ", map { $dbh->quote($_) } @vals) . ")";
    $dbh->do($sql);

    foreach my $clusterNum (keys %$clusterCenters) {
        my $sql = "INSERT INTO cluster_degree (cluster_num, accession, degree) VALUES (" .
                    $dbh->quote($clusterNum) . "," .
                    $dbh->quote($clusterCenters->{$clusterNum}->{id}) . "," .
                    $dbh->quote($clusterCenters->{$clusterNum}->{degree}) . ")";
        $dbh->do($sql);
    }

    foreach my $id (sort keys %$data) {
        my $sql = $self->getInsertStatement($EFI::GNN::Arrows::AttributesTable, $data->{$id}->{attributes}, $dbh);
        $dbh->do($sql);
        my $geneKey = $dbh->last_insert_id(undef, undef, undef, undef);
        $families{$data->{$id}->{attributes}->{family}} = 1;

        foreach my $nb (sort { $a->{num} cmp $b->{num} } @{ $data->{$id}->{neighbors} }) {
            $nb->{gene_key} = $geneKey;
            $sql = $self->getInsertStatement($EFI::GNN::Arrows::NeighborsTable, $nb, $dbh);
            $dbh->do($sql);
            $families{$nb->{family}} = 1;
        }
    }

    foreach my $id (sort keys %families) {
        my $sql = "INSERT INTO families (family) VALUES (" . $dbh->quote($id) . ")";
        $dbh->do($sql);
    }

    $dbh->commit;

    $dbh->disconnect;
}


sub writeUnmatchedIds {
    my $self = shift;
    my $file = shift;
    my $ids = shift;
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file","","");
    $dbh->{AutoCommit} = 0;

    my $createSql = getCreateUnmatchedIdsTableSql();
    $dbh->do($createSql);

    foreach my $idList (@$ids) {
        my $sql = "INSERT INTO unmatched (id_list) VALUES (" . $dbh->quote($idList) . ")";
        $dbh->do($sql);
    }

    $dbh->commit;
    $dbh->disconnect;
}


sub writeMatchedIds {
    my $self = shift;
    my $file = shift;
    my $ids = shift;
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file","","");
    $dbh->{AutoCommit} = 0;

    my $createSql = getCreateMatchedIdsTableSql();
    $dbh->do($createSql);

    foreach my $uniprotId (keys %$ids) {
        my $idList = join(",", @{$ids->{$uniprotId}});
        my $sql = "INSERT INTO matched (uniprot_id, id_list) VALUES (" . $dbh->quote($uniprotId) . ", " . $dbh->quote($idList) . ")";
        $dbh->do($sql);
    }

    $dbh->commit;
    $dbh->disconnect;
}


sub getCreateAttributeTableSql {
    my @statements;
    my $cols = getAttributeColsSql();
    $cols .= "\n                        , sort_order INTEGER";
    $cols .= "\n                        , strain VARCHAR(2000)";
    $cols .= "\n                        , cluster_num INTEGER";
    $cols .= "\n                        , organism VARCHAR(2000)";
    $cols .= "\n                        , is_bound INTEGER"; # 0 - not encountering any contig boundary; 1 - left; 2 - right; 3 - both
    $cols .= "\n                        , evalue REAL";

    my $sql = "CREATE TABLE $EFI::GNN::Arrows::AttributesTable ($cols)";
    push @statements, $sql;
    $sql = "CREATE INDEX ${EFI::GNN::Arrows::AttributesTable}_ac_index ON $EFI::GNN::Arrows::AttributesTable (accession)";
    push @statements, $sql;
    $sql = "CREATE INDEX ${EFI::GNN::Arrows::AttributesTable}_cl_num_index ON $EFI::GNN::Arrows::AttributesTable (cluster_num)";
    push @statements, $sql;
    return @statements;
}


sub getCreateNeighborTableSql {
    my $cols = getAttributeColsSql();
    $cols .= "\n                        , gene_key INTEGER";

    my @statements;
    push @statements, "CREATE TABLE $EFI::GNN::Arrows::NeighborsTable ($cols)";
    push @statements, "CREATE INDEX ${EFI::GNN::Arrows::NeighborsTable}_ac_id_index ON $EFI::GNN::Arrows::NeighborsTable (gene_key)";
    return @statements;
}

sub getAttributeColsSql {
    my $sql = <<SQL;
                        sort_key INTEGER PRIMARY KEY AUTOINCREMENT,
                        accession VARCHAR(10),
                        id VARCHAR(20),
                        num INTEGER,
                        family VARCHAR(1800),
                        start INTEGER,
                        stop INTEGER,
                        rel_start INTEGER,
                        rel_stop INTEGER,
                        direction VARCHAR(10),
                        type VARCHAR(10),
                        seq_len INTEGER,
                        taxon_id VARCHAR(20),
                        anno_status VARCHAR(255),
                        desc VARCHAR(255),
                        family_desc VARCHAR(255),
                        color VARCHAR(255)
SQL
    return $sql;
}

sub getCreateFamilyTableSql {
    my $sql = <<SQL;
CREATE TABLE families (family VARCHAR(1800));
SQL
    return $sql;
}

sub getCreateUnmatchedIdsTableSql {
    my $sql = <<SQL;
CREATE TABLE unmatched (id_list TEXT);
SQL
    return $sql;
}

sub getCreateMatchedIdsTableSql {
    my $sql = <<SQL;
CREATE TABLE matched (uniprot_id VARCHAR(10), id_list TEXT);
SQL
    return $sql;
}

sub getCreateDegreeTableSql {
    my @statements;
    my $sql = "CREATE TABLE cluster_degree (cluster_num INTEGER PRIMARY KEY, accession VARCHAR(10), degree INTEGER);";
    push @statements, $sql;
    $sql = "CREATE INDEX degree_cluster_num_index on cluster_degree (cluster_num)";
    push @statements, $sql;
    return @statements;
}


sub getCreateMetadataTableSql {
    my @statements;
    my $sql = "CREATE TABLE metadata (cooccurrence REAL, name VARCHAR(255), neighborhood_size INTEGER, type VARCHAR(10), sequence TEXT);";
    push @statements, $sql;
    return @statements;
}


sub getInsertStatement {
    my $self = shift;
    my $table = shift;
    my $attr = shift;
    my $dbh = shift;

    my $strainCol = exists $attr->{strain} ? ",strain" : "";
    my $clusterNumCol = exists $attr->{cluster_num} ? ",cluster_num" : "";
    my $geneKeyCol = exists $attr->{gene_key} ? ",gene_key" : "";
    my $organismCol = exists $attr->{organism} ? ",organism" : "";
    my $isBoundCol = exists $attr->{is_bound} ? ",is_bound" : "";
    my $orderCol = exists $attr->{sort_order} ? ",sort_order" : "";
    my $evalueCol = exists $attr->{evalue} ? ",evalue" : "";
    my $addlCols = $strainCol . $clusterNumCol . $geneKeyCol . $organismCol . $isBoundCol . $orderCol . $evalueCol;

    # If the family field is a fusion of multiple pfams, we get the color for each pfam in the fusion
    # as well as a color for the fusion.
    my $color = join(",", $self->{color_util}->getColorForPfam($attr->{family}));

    my $sql = "INSERT INTO $table (accession, id, num, family, start, stop, rel_start, rel_stop, direction, type, seq_len, taxon_id, anno_status, desc, family_desc, color $addlCols) VALUES (";
    $sql .= $dbh->quote($attr->{accession}) . ",";
    $sql .= $dbh->quote($attr->{id}) . ",";
    $sql .= $dbh->quote($attr->{num}) . ",";
    $sql .= $dbh->quote($attr->{family}) . ",";
    $sql .= $dbh->quote($attr->{start}) . ",";
    $sql .= $dbh->quote($attr->{stop}) . ",";
    $sql .= $dbh->quote($attr->{rel_start}) . ",";
    $sql .= $dbh->quote($attr->{rel_stop}) . ",";
    $sql .= $dbh->quote($attr->{direction}) . ",";
    $sql .= $dbh->quote($attr->{type}) . ",";
    $sql .= $dbh->quote($attr->{seq_len}) . ",";
    $sql .= $dbh->quote($attr->{taxon_id}) . ",";
    $sql .= $dbh->quote($attr->{anno_status}) . ",";
    $sql .= $dbh->quote($attr->{desc}) . ",";
    $sql .= $dbh->quote($attr->{family_desc}) . ",";
    $sql .= $dbh->quote($color);
    $sql .= "," . $dbh->quote($attr->{strain}) if exists $attr->{strain};
    $sql .= "," . $dbh->quote($attr->{cluster_num}) if exists $attr->{cluster_num};
    $sql .= "," . $dbh->quote($attr->{gene_key}) if exists $attr->{gene_key};
    $sql .= "," . $dbh->quote($attr->{organism}) if exists $attr->{organism};
    $sql .= "," . $dbh->quote($attr->{is_bound}) if exists $attr->{is_bound};
    $sql .= "," . $dbh->quote($attr->{sort_order}) if exists $attr->{sort_order};
    $sql .= "," . $dbh->quote($attr->{evalue}) if exists $attr->{evalue};
    $sql .= ")";

    return $sql;
}


#sub exportIdInfo {
#    my $self = shift;
#    my $sqliteFile = shift;
#    my $outFile = shift;
#
#    my $dbh = DBI->connect("dbi:SQLite:dbname=$sqliteFile","","");
#    
#    my $sql = "SELECT * FROM $EFI::GNN::Arrows::AttributesTable";
#    my $sth = $dbh->prepare($sql);
#    $sth->execute();
#
#    my %groupData;
#
#    while (my $row = $sth->fetchrow_hashref()) {
#        $groupData->{$row->{accession}} = {
#            gene_id => $row->{id},
#            seq_len => $row->{seq_len},
#            product => "",
#            organism => "", #$row->{strain},
#            taxonomy => "",
#            description => "",
#            contig_edge => 0, #TODO: compute this correctly
#            gene_key => $row->{sort_key},
#            neighbors => [],
#            position => $row->{num},
#        };
#    }
#
#    foreach my $id (sort keys %groupData) {
#        $sql = "SELECT * FROM $EFI::GNN::Arrows::NeighborsTable WHERE gene_key = " . $groupData{$id}->{gene_key} . " ORDER BY num";
#        $sth = $dbh->prepare($sql);
#        $sth->execute();
#
#        while (my $row = $sth->fetchrow_hashref()) {
#            my $num = $row->{num};
#            # Insert the main query/cluster ID into the middle of the neighbors where it belongs.
#            if ($row->{num} < $num) {
#                
#            }
#        }
#    }
#}



sub computeClusterCenters {
    my $self = shift;
    my $supernodes = shift;
    my $numbermatch = shift;
    my $singletons = shift;
    my $degrees = shift;

    my %centers;
    foreach my $clusterId (keys %$supernodes) {
        my @nodes = @{ $supernodes->{$clusterId} };
        my $clusterNum = $numbermatch->{$clusterId};

        if (exists $singletons->{$clusterId} and scalar @nodes > 1) {
            $centers{$clusterNum} = {degree => 1, id => $nodes[0]};
        } else {
            foreach my $acc (@nodes) {
                next if not exists $degrees->{$acc};
                if (not exists $centers{$clusterNum} or $degrees->{$acc} > $centers{$clusterNum}->{degree}) {
                    $centers{$clusterNum} = {degree => $degrees->{$acc}, id => $acc};
                }
            }
        }
    }

    return \%centers;
}


package DummyColorUtil;

sub new {
    my $class = shift;
    return bless({}, $class);
}

sub getColorForPfam {
    my $self = shift;
    my $fam = shift;
    return "#888888";
}

1;
