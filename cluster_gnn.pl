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
use EFI::GNN::Arrows;
use EFI::GNN::ColorUtil;


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


my $db = new EFI::Database(config_file_path => $configFile);
my $dbh = $db->getHandle();

mkdir $pfamDir  or die "Unable to create $pfamDir: $!"  if $pfamDir and not -d $pfamDir;
mkdir $idDir    or die "Unable to create $idDir: $!"    if $idDir and not -d $idDir;
mkdir $noneDir  or die "Unable to create $noneDir: $!"  if $noneDir and not -d $noneDir;


my $colorUtil = new EFI::GNN::ColorUtil(dbh => $dbh);
my %gnnArgs = (dbh => $dbh, incfrac => $cooccurrence, use_nnm => $useNewNeighborMethod, color_only => $colorOnly);
$gnnArgs{pfam_dir} = $pfamDir if $pfamDir and -d $pfamDir;
$gnnArgs{id_dir} = $idDir if $idDir and -d $idDir;
$gnnArgs{color_util} = $colorUtil;

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
        my $arrowTool = new EFI::GNN::Arrows(color_util => $colorUtil);
        my $clusterCenters = $arrowTool->computeClusterCenters($supernodes, $numbermatch, $singletons, $nodeDegrees);
        (my $jobName = $ssnin) =~ s%^.*/([^/]+)$%$1%;
        $jobName =~ s/\.(xgmml|zip)//g;
        my $arrowMeta = {
            cooccurrence => $cooccurrence,
            title => $jobName,
            neighborhood_size => $neighborhoodSize,
            type => "gnn"
        };
        $arrowTool->writeArrowData($accessionData, $clusterCenters, $arrowDataFile, $arrowMeta);
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


