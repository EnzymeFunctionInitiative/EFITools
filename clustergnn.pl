#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


#version 1.0.0 added support for coloring SSNs only, and refactored code, and submits to queue.
#version 0.2.4 hub and spoke node attribute update
#version 0.2.3 paired pfams now in combined hub nodes
#version 0.2.2 now warn if top level structures are not a node or an edge, a fix to allow cytoscape edited networks to function.
#version 0.2.2 Changed supercluster node attribue in colored ssn from string to integer
#version 0.2.2 Added SSN_Cluster_Size to stats table
#version 0.2.2 Added column headers to stats table
#version 0.03
#added error checking on input values
#improved performance of xgmml parsing by indexingg the dom
#change mysql so that the session will restart if it ever disconnects
#changed syntax -xgmml is not -ssnin
#the graph names of the output xgmmls are now based off the graph name of the input xgmml
#version 0.02
#fixed issues that would prevent cytoscape exported xgmml files from working
#version 0.01
#initial version

use strict;

use FindBin;
use Getopt::Long;
use XML::LibXML;
use IO;
use XML::Writer;
use XML::LibXML::Reader;
use JSON;
use DBI;
use List::MoreUtils qw(uniq);

use lib $FindBin::Bin . "/lib";
use EFI::Database;
use EFI::GNN;


my ($ssnin, $neighborhoodSize, $warningFile, $gnn, $ssnout, $cooccurrence, $stats, $pfamhubfile, $configFile,
    $pfamDir, $idDir, $noneDir, $idOutputFile, $arrowDataFile, $printPrettyJson, $dontUseNewNeighborMethod,
    $pfamCoocTable, $hubCountFile);

my $result = GetOptions(
    "ssnin=s"           => \$ssnin,
    "n|nb-size=s"       => \$neighborhoodSize,
    "warning-file=s"    => \$warningFile,
    "gnn=s"             => \$gnn,
    "ssnout=s"          => \$ssnout,
    "incfrac|cooc=i"    => \$cooccurrence,
    "stats=s"           => \$stats,
    "pfam=s"            => \$pfamhubfile,
    "config=s"          => \$configFile,
    "pfam-dir=s"        => \$pfamDir,
    "id-dir=s"          => \$idDir,
    "none-dir=s"        => \$noneDir,
    "id-out=s"          => \$idOutputFile,
    "arrow-file=s"      => \$arrowDataFile,
    "cooc-table=s"      => \$pfamCoocTable,
    "hub-count-file=s"  => \$hubCountFile,
    "json-pretty"       => \$printPrettyJson,
    "disable-nnm"       => \$dontUseNewNeighborMethod,
);

my $usage = <<USAGE
usage: $0 -ssnin <filename> -n <positive integer> -nomatch <filename> -gnn <filename> -ssnout <filename>
    -ssnin              name of original ssn network to process
    -nb-size            distance (+/-) to search for neighbors
    -gnn                filename of genome neighborhood network output file
    -ssnout             output filename for colorized sequence similarity network
    -warning-file       output file that contains sequences without neighbors or matches
    -cooc               co-occurrence
    -stats              file to output tabular statistics to
    -pfam               file to output PFAM hub GNN to
    -id-dir             path to directory to output lists of IDs (one file/list per cluster number)
    -pfam-dir           path to directory to output PFAM cluster data (one file/list per cluster number)
    -id-out             path to a file to save the ID, cluster #, cluster color
    -arrow-file         path to a file to save the neighbor data necessary to draw arrows
    -cooc-table         path to a file to save the pfam/cooccurrence table data to
    -hub-count-file     path to a file to save the sequence count for each GNN hub node
    -config             configuration file for database info, etc.
USAGE
;



if (not -f $configFile and not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
} elsif (not -f $configFile) {
    $configFile = $ENV{EFICONFIG};
}

#error checking on input values

unless(-s $ssnin){
    die "-ssnin $ssnin does not exist or has a zero size\n$usage";
}

unless($neighborhoodSize>0){
    die "-nb-size $neighborhoodSize must be an integer greater than zero\n$usage";
}


if($cooccurrence=~/^\d+$/){
    $cooccurrence=$cooccurrence/100;
}else{
    if(defined $cooccurrence){
        die "incfrac must be an integer\n";
    }
    $cooccurrence=0.20;  
}

my $useNewNeighborMethod = 0;
if (not defined $dontUseNewNeighborMethod) {
    $useNewNeighborMethod = 1;
}

my $colorOnly = ($ssnout and not $gnn and not $pfamhubfile) ? 1 : 0;

(my $jobName = $ssnin) =~ s%^.*/([^/]+)$%$1%;
$jobName =~ s/\.(xgmml|zip)//g;


my $db = new EFI::Database(config_file_path => $configFile);
my $dbh = $db->getHandle();

mkdir $pfamDir  or die "Unable to create $pfamDir: $!"  if $pfamDir and not -d $pfamDir;
mkdir $idDir    or die "Unable to create $idDir: $!"    if $idDir and not -d $idDir;
mkdir $noneDir  or die "Unable to create $noneDir: $!"  if $noneDir and not -d $noneDir;

my %gnnArgs = (dbh => $dbh, incfrac => $cooccurrence, use_nnm => $useNewNeighborMethod, color_only => $colorOnly);
$gnnArgs{pfam_dir} = $pfamDir if $pfamDir and -d $pfamDir;
$gnnArgs{id_dir} = $idDir if $idDir and -d $idDir;

my $util = new EFI::GNN(%gnnArgs);

if($stats=~/\w+/){
    open STATS, ">$stats" or die "could not write to $stats\n";
    print STATS "Cluster_Number\tPFAM\tPFAM_Description\tCluster_Fraction\tAvg_Distance\tSSN_Cluster_Size\n";
}else{
    open STATS, ">/dev/null" or die "could nto dump stats info to dev null\n";
}

my %nodehash=();
my %constellations=();
my %supernodes=();
my %nodenames=();
my %numbermatch=();


#nodehash correlates accessions in a node to the labeled accession of a node, this is for drilling down into repnode networks
#nodehash key is an accession
#constellations maps accessions to a supernode number
#constellations key is an accession
#supernodes is a hash of arrays that contain all of the accessions within a constellation
#key for supernodes are the intergers from %constellations
#key for pams is a pfam number.
#nodenames maps the id from nodes to accession number, this allows you to run this script on cytoscape xgmml exports

print "read xgmml file, get list of nodes and edges\n";

my $reader=XML::LibXML::Reader->new(location => $ssnin);
my ($title, $nodes, $edges, $nodeDegrees) = $util->getNodesAndEdges($reader);


print "found ".scalar @{$nodes}." nodes\n";
print "found ".scalar @{$edges}." edges\n";
print "graph name is $title\n";

my ($nodehash, $nodenames, $nodeMap) = $util->getNodes($nodes);

#my $includeSingletonsInSsn = (not defined $gnn or not length $gnn) and (not defined $pfamhubfile or not length $pfamhubfile);
# We include singletons by default, although if they don't have any represented nodes they won't be colored in the SSN.
my $includeSingletons = 1;
my ($supernodes, $constellations, $singletons) = $util->getClusters($nodehash, $nodenames, $edges, undef, $includeSingletons);

print "find neighbors\n\n";

my $warning_fh;
if ($gnn and $warningFile) { #$nomatch and $noneighfile) {
    open($warning_fh, ">$warningFile") or die "cannot write file of no-match/no-neighbor warnings for accessions\n";
} else {
    open($warning_fh, ">/dev/null") or die "cannot write file of no-match/no-neighbor warnings to /dev/null\n";
}
print $warning_fh "UniProt ID\tNo Match/No Neighbor\n";


my $useExistingNumber = $util->hasExistingNumber($nodes);
my ($numbermatch, $numberOrder) = $util->numberClusters($supernodes, $useExistingNumber);

my $gnnData = {};
if (not $colorOnly) {
    my $useCircTest = 1;
    my ($clusterNodes, $withneighbors, $noMatchMap, $noNeighborMap, $genomeIds, $noneFamily, $accessionData) =
            $util->getClusterHubData($supernodes, $neighborhoodSize, $warning_fh, $useCircTest, $numberOrder, $numbermatch);

    if ($pfamCoocTable) {
        my $pfamTable = $util->getPfamCooccurrenceTable($clusterNodes, $withneighbors, $numbermatch, $supernodes, $singletons);
        writePfamCoocTable($pfamCoocTable, $pfamTable);
    }

    if ($gnn) {
        print "Writing Cluster Hub GNN\n";
        my $gnnoutput=new IO::File(">$gnn");
        my $gnnwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $gnnoutput);
        $util->writeClusterHubGnn($gnnwriter, $clusterNodes, $withneighbors, $numbermatch, $supernodes, $singletons);
    }
    
    if ($pfamhubfile) {
        print "Writing Pfam Hub GNN\n";
        my $pfamoutput=new IO::File(">$pfamhubfile");
        my $pfamwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $pfamoutput);
        $util->writePfamHubGnn($pfamwriter, $clusterNodes, $withneighbors, $numbermatch, $supernodes);
        $util->writePfamNoneClusters($noneDir, $noneFamily, $numbermatch);
    }

    if ($arrowDataFile) {
        print "Writing to arrow data file\n";
        my $clusterCenters = computeClusterCenters($supernodes, $numbermatch, $singletons, $nodeDegrees);
        writeArrowData($accessionData, $clusterCenters, $arrowDataFile, $util);
        #TODO: implement this code
    }

    if ($hubCountFile) {
        print "Writing to GNN hub sequence count file\n";
        writeHubCountFile($clusterNodes, $withneighbors, $supernodes, $numbermatch, $hubCountFile);
    }
    
    $gnnData->{noMatchMap} = $noMatchMap;
    $gnnData->{noNeighborMap} = $noNeighborMap;
    $gnnData->{genomeIds} = $genomeIds;
}

if ($ssnout) {
    print "write out colored ssn network ".scalar @{$nodes}." nodes and ".scalar @{$edges}." edges\n";
    my $output=new IO::File(">$ssnout");
    my $writer=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $output);

    $util->writeColorSsn($nodes, $edges, $writer, $numbermatch, $constellations, $nodenames, $supernodes, $gnnData);
}

close($warning_fh);

$util->writeIdMapping($idOutputFile, $numbermatch, $constellations, $supernodes) if $idOutputFile;
#$util->closeClusterMapFiles();
$util->finish();



print "$0 finished\n";












sub writePfamCoocTable {
    my $file = shift;
    my $pfamTable = shift;

    my @pfams = sort keys %$pfamTable;
    my @clusters = uniq sort { $a <=> $b }  map { keys %{$pfamTable->{$_}} } @pfams;

    open PFAMFILE, ">$file" or die "Unable to create the Pfam cooccurrence table $file: $!";

    print PFAMFILE join("\t", "PFAM", @clusters), "\n";
    foreach my $pf (@pfams) {
        next if $pf =~ /none/i;
        my $line = $pf;
        foreach my $cluster (@clusters) {
            $line .= "\t" if $line;
            if (exists $pfamTable->{$pf}->{$cluster}) {
                $line .= $pfamTable->{$pf}->{$cluster};
            } else {
                $line .= "0";
            }
        }
        $line .= "\n";
        print PFAMFILE $line;
    }

    close PFAMFILE;
}


sub writeHubCountFile {
    my $clusterNodes = shift;
    my $withneighbors = shift;
    my $supernodes = shift;
    my $numbermatch = shift;
    my $file = shift;

    open HUBFILE, ">$file" or die "Unable to create the hub count file $file: $!";

    print HUBFILE join("\t", "ClusterNum", "NumQueryableSeq", "TotalNumSeq"), "\n";
    foreach my $cluster (sort hubCountSortFn keys %$clusterNodes) {
        my $numQueryableSeq = scalar @{ $withneighbors->{$cluster} };
        my $totalSeq = scalar @{ $supernodes->{$cluster} };
        my $clusterNum = $numbermatch->{$cluster};
        my $line = join("\t", $clusterNum, $numQueryableSeq, $totalSeq);
        print HUBFILE $line, "\n";
    }

    close HUBFILE;
}


sub hubCountSortFn {
    if (not exists $numbermatch->{$a} and not exists $numbermatch->{$b}) {
        return 0;
    } elsif (not exists $numbermatch->{$a}) {
        return 1;
    } elsif (not exists $numbermatch->{$b}) {
        return -1;
    } else {
        return $numbermatch->{$a} <=> $numbermatch->{$b};
    }
}


sub writeArrowData {
    my $data = shift;
    my $clusterCenters = shift;
    my $file = shift;
    my $colorizer = shift;

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

    my $sql = "INSERT INTO metadata (coocurrence, neighborhood_size, name) VALUES(" .
        $dbh->quote($cooccurrence) . "," .
        $dbh->quote($neighborhoodSize) . "," .
        $dbh->quote($jobName) . ")";
    $dbh->do($sql);

    foreach my $clusterNum (keys %$clusterCenters) {
        my $sql = "INSERT INTO cluster_degree (cluster_num, accession, degree) VALUES (" .
                    $dbh->quote($clusterNum) . "," .
                    $dbh->quote($clusterCenters->{$clusterNum}->{id}) . "," .
                    $dbh->quote($clusterCenters->{$clusterNum}->{degree}) . ")";
        $dbh->do($sql);
    }

    foreach my $id (sort keys %$data) {
        my $sql = getInsertStatement("attributes", $data->{$id}->{attributes}, $dbh, $colorizer);
        $dbh->do($sql);
        my $geneKey = $dbh->last_insert_id(undef, undef, undef, undef);
        $families{$data->{$id}->{attributes}->{family}} = 1;

        foreach my $nb (sort { $a->{num} cmp $b->{num} } @{ $data->{$id}->{neighbors} }) {
            $nb->{gene_key} = $geneKey;
            $sql = getInsertStatement("neighbors", $nb, $dbh, $colorizer);
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


sub getCreateAttributeTableSql {
    my @statements;
    my $cols = getAttributeColsSql();
    $cols .= "\n                        , sort_order INTEGER";
    $cols .= "\n                        , strain VARCHAR(2000)";
    $cols .= "\n                        , cluster_num INTEGER";
    $cols .= "\n                        , organism VARCHAR(2000)";
    $cols .= "\n                        , is_bound INTEGER"; # 0 - not encountering any contig boundary; 1 - left; 2 - right; 3 - both

    my $sql = "CREATE TABLE attributes ($cols)";
    push @statements, $sql;
    $sql = "CREATE INDEX attributes_ac_index ON attributes (accession)";
    push @statements, $sql;
    $sql = "CREATE INDEX attributes_cl_num_index ON attributes (cluster_num)";
    push @statements, $sql;
    return @statements;
}


sub getCreateNeighborTableSql {
    my $cols = getAttributeColsSql();
    $cols .= "\n                        , gene_key INTEGER";

    my @statements;
    push @statements, "CREATE TABLE neighbors ($cols)";
    push @statements, "CREATE INDEX neighbor_ac_id_index ON neighbors (gene_key)";
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
                        color VARCHAR(7)
SQL
    return $sql;
}

sub getCreateFamilyTableSql {
    my $sql = <<SQL;
CREATE TABLE families (family VARCHAR(1800));
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
    my $sql = "CREATE TABLE metadata (cooccurrence REAL, name VARCHAR(255), neighborhood_size INTEGER);";
    push @statements, $sql;
    return @statements;
}


sub getInsertStatement {
    my $table = shift;
    my $attr = shift;
    my $dbh = shift;
    my $colorizer = shift;

    my $strainCol = exists $attr->{strain} ? ",strain" : "";
    my $clusterNumCol = exists $attr->{cluster_num} ? ",cluster_num" : "";
    my $geneKeyCol = exists $attr->{gene_key} ? ",gene_key" : "";
    my $organismCol = exists $attr->{organism} ? ",organism" : "";
    my $isBoundCol = exists $attr->{is_bound} ? ",is_bound" : "";
    my $orderCol = exists $attr->{sort_order} ? ",sort_order" : "";
    my $addlCols = $strainCol . $clusterNumCol . $geneKeyCol . $organismCol . $isBoundCol . $orderCol;

    my $color = $colorizer->getColorForPfam($attr->{family});

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
    $sql .= ")";

    return $sql;
}

sub computeClusterCenters {
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

