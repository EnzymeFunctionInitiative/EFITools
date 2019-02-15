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
use warnings;

use FindBin;
use Getopt::Long;
use XML::LibXML;
use IO qw(File);
use XML::Writer;
use XML::LibXML::Reader;
use JSON;
use DBI;
use List::MoreUtils qw(uniq);
use Time::HiRes qw(time);
use Storable;
use Data::Dumper;

use lib $FindBin::Bin . "/lib";
use EFI::Database;
use EFI::GNN;
use EFI::GNN::Base;
use EFI::GNN::Arrows;
use EFI::GNN::ColorUtil;
use EFI::GNN::AnnotationUtil;


my ($ssnin, $neighborhoodSize, $warningFile, $gnn, $ssnout, $cooccurrence, $statsFile, $pfamhubfile, $configFile,
    $pfamDir, $noneDir, $idOutputFile, $idOutputDomainFile, $arrowDataFile, $dontUseNewNeighborMethod,
    $uniprotIdDir, $uniref50IdDir, $uniref90IdDir,
    $pfamCoocTable, $hubCountFile, $allPfamDir, $splitPfamDir, $allSplitPfamDir, $clusterSizeFile, $swissprotClustersDescFile,
    $swissprotSinglesDescFile, $parentDir, $renumberClusters, $disableCache, $skipIdMapping, $skipOrganism, $debug);

my $result = GetOptions(
    "ssnin=s"               => \$ssnin,
    "n|nb-size=s"           => \$neighborhoodSize,
    "warning-file=s"        => \$warningFile,
    "gnn=s"                 => \$gnn,
    "ssnout=s"              => \$ssnout,
    "incfrac|cooc=i"        => \$cooccurrence,
    "stats=s"               => \$statsFile,
    "cluster-sizes=s"       => \$clusterSizeFile,
    "sp-clusters-desc=s"    => \$swissprotClustersDescFile,
    "sp-singletons-desc=s"  => \$swissprotSinglesDescFile,
    "pfam=s"                => \$pfamhubfile,
    "config=s"              => \$configFile,
    "pfam-dir=s"            => \$pfamDir,
    "all-pfam-dir=s"        => \$allPfamDir, # all Pfams, not just those within user-specified cooccurrence threshold
    "split-pfam-dir=s"      => \$splitPfamDir, # like -pfam-dir, but the PFAMs are in individual files
    "all-split-pfam-dir=s"  => \$allSplitPfamDir, # like -all-pfam-dir, but the PFAMs are in individual files
    "uniprot-id-dir=s"      => \$uniprotIdDir,
    "uniref50-id-dir=s"     => \$uniref50IdDir,
    "uniref90-id-dir=s"     => \$uniref90IdDir,
    "none-dir=s"            => \$noneDir,
    "id-out=s"              => \$idOutputFile,
    "id-out-domain=s"       => \$idOutputDomainFile, # if there is no domain info on the IDs, this isn't output even if the arg is present.
    "arrow-file=s"          => \$arrowDataFile,
    "cooc-table=s"          => \$pfamCoocTable,
    "hub-count-file=s"      => \$hubCountFile,
    "parent-dir=s"          => \$parentDir, # directory of parent job (if specified, the neighbor results are pulled from the storable files there).
    "renumber-clusters"     => \$renumberClusters,
    "disable-nnm"           => \$dontUseNewNeighborMethod,
    "disable-cache"         => \$disableCache,
    "skip-id-mapping"       => \$skipIdMapping,
    "skip-organism"         => \$skipOrganism,
    "debug"                 => \$debug,
);

my $usage = <<USAGE
usage: $0 -ssnin <filename> -ssnout <filename> -gnn <filename> -pfam <filename>
        -nb-size <positive integer>

    -ssnin              name of original ssn network to process
    -ssnout             output filename for colorized sequence similarity
                        network
    -gnn                filename of genome neighborhood network output file
    -pfam               file to output PFAM hub GNN to
    -nb-size            distance (+/-) to search for neighbors

    -warning-file       output file that contains sequences without neighbors
                        or matches
    -cooc               co-occurrence
    -stats              file to output tabular statistics to
    -cluster-size       file to output cluster sizes to
    -sp-desc            file to write swissprot descriptions to for metanodes
    -uniprot-id-dir     path to directory to output lists of UniProt IDs
                        (one file/list per cluster number)
    -uniref50-id-dir    path to directory to output lists of UniRef50 IDs
                        (one file/list per cluster number)
    -uniref90-id-dir    path to directory to output lists of UniRef90 IDs
                        (one file/list per cluster number)
    -pfam-dir           path to directory to output PFAM cluster data (one
                        file/list per cluster number)
    -all-pfam-dir       path to directory to output all PFAM cluster data (one
                        file/list per cluster number), regardless of
                        cooccurrence threshold
    -split-pfam-dir     path to directory to output PFAM cluster data,
                        separated into one filer per PFAM not domain
    -id-out             path to a file to save the ID, cluster #, cluster color;
                        IDs are without domain info, if any
    -id-out-domain      path to a file to save the ID, cluster #, cluster color;
                        IDs are with domain info, if present on the ID. If no
                        nodes have domain info, then this file isn't output even
                        if it's provided as an argument
    -arrow-file         path to a file to save the neighbor data necessary to
                        draw arrows
    -cooc-table         path to file to save the pfam/cooccurrence table data to
    -hub-count-file     path to a file to save the sequence count for each GNN
                        hub node

    -parent-dir         directory of parent job to pull storables (numbering
                        and neighborhood data) from
    -renumber-clusters  renumber any clusters that already have cluster numbers

    -config             configuration file for database info, etc.

-ssnin and -ssnout are mandatory. If -ssnin is given and -gnn and -pfam are not
given, then the output SSN is simply cluster-numbered and colored.  Otherwise,
-nb-size is the only other required argument.
USAGE
;



if ((not $configFile or not -f $configFile) and not exists $ENV{EFICONFIG}) {
    die "Either the configuration $configFile file or the EFICONFIG environment variable must be set\n$usage";
} elsif (not $configFile or not -f $configFile) {
    $configFile = $ENV{EFICONFIG};
}

#error checking on input values

if (not $ssnin or not -s $ssnin){
    $ssnin = "" if not $ssnin;
    die "-ssnin $ssnin does not exist or has a zero size\n$usage";
}

my $hasParent = $parentDir and -d $parentDir;

my $colorOnly = ($ssnout and not $gnn and not $pfamhubfile and not $hasParent) ? 1 : 0;
$neighborhoodSize = 0 if not $neighborhoodSize;

if (not $colorOnly and $neighborhoodSize < 1) {
    die "-nb-size $neighborhoodSize must be an integer greater than zero\n$usage";
}


if (defined $cooccurrence and $cooccurrence =~ /^\d+$/) {
    $cooccurrence = $cooccurrence / 100;
} else {
    if (not $colorOnly and defined $cooccurrence) {
        die "incfrac must be an integer\n";
    }
    $cooccurrence=0.20;  
}

my $useNewNeighborMethod = 0;
if (not defined $dontUseNewNeighborMethod) {
    $useNewNeighborMethod = 1;
}

$renumberClusters = defined $renumberClusters ? 1 : 0;
my $enableCache = defined $disableCache ? 0 : 1;
$skipIdMapping = defined $skipIdMapping ? 1 : 0;
$skipOrganism = defined $skipOrganism ? 1 : 0;
$idOutputDomainFile = "" if not defined $idOutputDomainFile;
$idOutputFile = "" if not defined $idOutputFile;
$debug = defined $debug ? 1 : 0;


my $idBaseOutputDir = $ENV{PWD};
$uniprotIdDir = "$idBaseOutputDir/UniProt" if not $uniprotIdDir;
$uniref50IdDir = "$idBaseOutputDir/UniRef50" if not $uniref50IdDir;
$uniref90IdDir = "$idBaseOutputDir/UniRef90" if not $uniref90IdDir;



my $db = new EFI::Database(config_file_path => $configFile);
my $dbh = $db->getHandle();

mkdir $pfamDir          or die "Unable to create $pfamDir: $!"          if $pfamDir and not -d $pfamDir;
mkdir $allPfamDir       or die "Unable to create $allPfamDir: $!"       if $allPfamDir and not -d $allPfamDir;
mkdir $splitPfamDir     or die "Unable to create $splitPfamDir: $!"     if $splitPfamDir and not -d $splitPfamDir;
mkdir $allSplitPfamDir  or die "Unable to create $allSplitPfamDir: $!"  if $allSplitPfamDir and not -d $allSplitPfamDir;
mkdir $uniprotIdDir     or die "Unable to create $uniprotIdDir: $!"     if $uniprotIdDir and not -d $uniprotIdDir;
mkdir $uniref50IdDir    or die "Unable to create $uniref50IdDir: $!"    if $uniref50IdDir and not -d $uniref50IdDir;
mkdir $uniref90IdDir    or die "Unable to create $uniref90IdDir: $!"    if $uniref90IdDir and not -d $uniref90IdDir;
mkdir $noneDir          or die "Unable to create $noneDir: $!"          if $noneDir and not -d $noneDir;


my $colorUtil = new EFI::GNN::ColorUtil(dbh => $dbh);
my %gnnArgs = (dbh => $dbh, incfrac => $cooccurrence, use_nnm => $useNewNeighborMethod, color_only => $colorOnly);
$gnnArgs{pfam_dir} = $pfamDir if $pfamDir and -d $pfamDir;
$gnnArgs{all_pfam_dir} = $allPfamDir if $allPfamDir and -d $allPfamDir;
$gnnArgs{split_pfam_dir} = $splitPfamDir if $splitPfamDir and -d $splitPfamDir;
$gnnArgs{all_split_pfam_dir} = $allSplitPfamDir if $allSplitPfamDir and -d $allSplitPfamDir;
#$gnnArgs{uniprot_id_dir} = $uniprotIdDir if $uniprotIdDir and -d $uniprotIdDir;
#$gnnArgs{uniref50_id_dir} = $uniref50IdDir if $uniref50IdDir and -d $uniref50IdDir;
#$gnnArgs{uniref90_id_dir} = $uniref90IdDir if $uniref90IdDir and -d $uniref90IdDir;
$gnnArgs{color_util} = $colorUtil;


my ($uniprotSingletonsFile, $uniref50SingletonsFile, $uniref90SingletonsFile);
$uniprotSingletonsFile = "$uniprotIdDir/singletons_UniProt.txt" if $uniprotIdDir and $idOutputFile;
$uniref50SingletonsFile = "$uniref50IdDir/singletons_UniRef50.txt" if $uniref50IdDir and $idOutputFile;
$uniref90SingletonsFile = "$uniref90IdDir/singletons_UniRef90.txt" if $uniref90IdDir and $idOutputFile;


my $util = new EFI::GNN(%gnnArgs);


timer("-----all-------");

print "read xgmml file, get list of nodes and edges\n";

timer("getNodesAndEdges");
my $reader = XML::LibXML::Reader->new(location => $ssnin);
my ($title, $numNodes, $numEdges, $nodeDegrees) = $util->getNodesAndEdges($reader);
timer("getNodesAndEdges");

print "found $numNodes nodes\n";
print "found $numEdges edges\n";
print "graph name is $title\n";

timer("getNodes");
print "parsing nodes for accession information\n";
my ($swissprotDesc) = $util->getNodes();
timer("getNodes");

timer("getTaxonIdsAndSpecies");
print "getting species and taxon IDs\n";
my $annoUtil = new EFI::GNN::AnnotationUtil(dbh => $dbh);
my $allIds = $util->getAllNetworkIds();
my ($species, $taxonIds) = ({}, {});
if (not $skipOrganism) {
    ($species, $taxonIds) = $annoUtil->getMultipleAnnotations($allIds);
}
timer("getTaxonIdsAndSpecies");

#my $includeSingletonsInSsn = (not defined $gnn or not length $gnn) and (not defined $pfamhubfile or not length $pfamhubfile);
# We include singletons by default, although if they don't have any represented nodes they won't be colored in the SSN.
my $includeSingletons = 1;
timer("getClusters");
print "determining clusters\n";
$util->getClusters($includeSingletons);
timer("getClusters");

my $warning_fh;
if ($gnn and $warningFile) { #$nomatch and $noneighfile) {
    open($warning_fh, ">$warningFile") or warn "cannot write file of no-match/no-neighbor warnings for accessions\n";
} else {
    open($warning_fh, ">/dev/null") or die "cannot write file of no-match/no-neighbor warnings to /dev/null\n";
}
print $warning_fh "UniProt ID\tNo Match/No Neighbor\n";

my $nbCacheFile = "$ENV{PWD}/storable.hubdata";
my $numCacheFile = "$ENV{PWD}/storable.numbering";
if ($hasParent) {
    if (-f "$parentDir/storable.hubdata") {
        $numCacheFile = "$parentDir/storable.numbering";
        $nbCacheFile = "$parentDir/storable.hubdata";
    }
}

timer("numberClusters");
print "numbering the clusters\n";
my ($useExistingNumber) = (0);
my $ssnSequenceVersion = $util->getSequenceSource();
$util->numberClusters($useExistingNumber);
my $ClusterIdMap = $util->getClusterIdMap(); # This is not to be used anywhere but in the sort function below.
timer("numberClusters");

timer("idMapping");
my $hasDomain = 0;
if (not $skipIdMapping) {
    print "saving the cluster-protein ID mapping tables\n";
    my ($uniprotMap, $uniprotDomainMap, $uniref50Map, $uniref90Map) = getClusterToIdMapping($dbh, $util, $ssnSequenceVersion);
    $hasDomain = scalar keys %$uniprotDomainMap;
    saveClusterIdFiles(
        $uniprotMap, $uniprotDomainMap, $uniref50Map, $uniref90Map,
        $uniprotIdDir, $uniref50IdDir, $uniref90IdDir,
        $uniprotSingletonsFile, $uniref50SingletonsFile, $uniref90SingletonsFile,
    );
}
$idOutputDomainFile = "" if not $hasDomain;
timer("idMapping");


my $gnnData = {};
if (not $colorOnly) { # and not $skipIdMapping) {
    print "finding neighbors\n";
    my $useCircTest = 1;
    timer("getClusterHubData");
    my ($clusterNodes, $withNeighbors, $noMatchMap, $noNeighborMap, $genomeIds, $noneFamily, $accessionData);
    my ($allNbAccDataForArrows);
    if ($hasParent and -f $nbCacheFile) {
        print "USING PARENT NEIGHBOR DATA with $neighborhoodSize\n";
        my $data = retrieve($nbCacheFile);
        # The cluster number ($data->{accessionData}->{$accession}->{attributes}->{cluster_num}) is updated with new cluster number in this function.
        ($clusterNodes, $withNeighbors, $noMatchMap, $noNeighborMap, $genomeIds, $noneFamily, $accessionData) =
            $util->filterClusterHubData($data, $neighborhoodSize);
        $allNbAccDataForArrows = $accessionData;
    } else {
        print "computing cluster hub/neighbor data\n";
        my ($allNbAccessionData, $allPfamData);
        ($clusterNodes, $withNeighbors, $noMatchMap, $noNeighborMap, $genomeIds, $noneFamily, $accessionData, $allNbAccessionData, $allPfamData) =
                $util->getClusterHubData($neighborhoodSize, $warning_fh, $useCircTest);
        my $data = {};
        $data->{allPfamData} = $allPfamData;
        $data->{noMatchMap} = $noMatchMap;
        $data->{noNeighborMap} = $noNeighborMap;
        $data->{genomeIds} = $genomeIds;
        $data->{noneFamily} = $noneFamily;
        $data->{accessionData} = $allNbAccessionData;
        store($data, $nbCacheFile) if $nbCacheFile and $enableCache;
        $allNbAccDataForArrows = $allNbAccessionData;
    }
    timer("getClusterHubData");

    #TODO: save the all* data to a temp file for reading later for filtering


    timer("getPfamCooccurrenceTable");
    if ($pfamCoocTable) {
        print "getting pfam cooccurrence table\n";
        my $pfamTable = $util->getPfamCooccurrenceTable($clusterNodes, $withNeighbors);
        writePfamCoocTable($pfamCoocTable, $pfamTable);
    }
    timer("getPfamCooccurrenceTable");

    timer("writeClusterHubGnn");
    if ($gnn) {
        print "writing cluster hub GNN\n";
        my $gnnoutput=new IO::File(">$gnn");
        my $gnnwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $gnnoutput);
        $util->writeClusterHubGnn($gnnwriter, $clusterNodes, $withNeighbors);
    }
    timer("writeClusterHubGnn");
    
    timer("writePfamHubGnn");
    if ($pfamhubfile) {
        print "writing pfam hub GNN\n";
        my $pfamoutput=new IO::File(">$pfamhubfile");
        my $pfamwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $pfamoutput);
        $util->writePfamHubGnn($pfamwriter, $clusterNodes, $withNeighbors);
        $util->writePfamNoneClusters($noneDir, $noneFamily);
    }
    timer("writePfamHubGnn");

    timer("writeArrows");
    if ($arrowDataFile) {
        print "writing to arrow data file\n";
        my $arrowTool = new EFI::GNN::Arrows(color_util => $colorUtil);
        my $clusterCenters = $arrowTool->computeClusterCenters($util, $nodeDegrees);
        (my $jobName = $ssnin) =~ s%^.*/([^/]+)$%$1%;
        $jobName =~ s/\.(xgmml|zip)//g;
        my $arrowMeta = {
            cooccurrence => $cooccurrence,
            title => $jobName,
            #neighborhood_size => $neighborhoodSize,
            neighborhood_size => EFI::GNN::MAX_NB_SIZE,
            type => "gnn"
        };
        $arrowTool->writeArrowData($allNbAccDataForArrows, $clusterCenters, $arrowDataFile, $arrowMeta);
    }
    timer("writeArrows");

    timer("writeHubCountFile");
    if ($hubCountFile) {
        print "writing to GNN hub sequence count file\n";
        writeHubCountFile($util, $clusterNodes, $withNeighbors, $hubCountFile);
    }
    timer("writeHubCountFile");
    
    $gnnData->{noMatchMap} = $noMatchMap;
    $gnnData->{noNeighborMap} = $noNeighborMap;
    $gnnData->{genomeIds} = $genomeIds;
    $gnnData->{accessionData} = $accessionData;
}

timer("writeColorSsn");
if ($ssnout) {
    print "write out colored ssn network $numNodes nodes and $numEdges edges\n";
    my $output=new IO::File(">$ssnout");
    my $writer=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $output);

    $util->writeColorSsn($writer, $gnnData);
}
timer("writeColorSsn");

close($warning_fh);

timer("wrapup");
print "writing mapping and statistics\n";
$util->writeIdMapping($idOutputFile, $idOutputDomainFile, $taxonIds, $species) if $idOutputFile;
$util->writeSsnStats($swissprotDesc, $statsFile, $clusterSizeFile, $swissprotClustersDescFile, $swissprotSinglesDescFile) if $statsFile and $clusterSizeFile and $swissprotClustersDescFile and $swissprotSinglesDescFile;
$util->finish();
timer("wrapup");


print "$0 finished. happy happy happy!\n";

timer("-----all-------");
timer(action => "print");






my %_timers;
my @_tc;

sub timer {
    my @parms = @_;

    if (scalar @parms > 1 and $parms[0] eq "action" and $parms[1] eq "print") {
        foreach my $id (@_tc) {
            print "$id\t$_timers{$id}\n";
        }
    } else {
        my $id = scalar @parms ? $parms[0] : "default";
        if (exists $_timers{$id}) {
            $_timers{$id} = time() - $_timers{$id};
        } else {
            $_timers{$id} = time();
            push @_tc, $id;
        }
    }
}


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
    my $util = shift;
    my $clusterNodes = shift;
    my $withNeighbors = shift;
    my $file = shift;

    open HUBFILE, ">$file" or die "Unable to create the hub count file $file: $!";

    print HUBFILE join("\t", "ClusterNum", "NumQueryableSeq", "TotalNumSeq"), "\n";
    foreach my $clusterId (sort hubCountSortFn keys %$clusterNodes) {
        my $numQueryableSeq = scalar @{ $withNeighbors->{$clusterId} };
        my $clusterNum = $util->getClusterNumber($clusterId);

        my $ids = $util->getIdsInCluster($clusterNum, ALL_IDS);
        my $totalSeq = scalar @$ids;

        my $line = join("\t", $clusterNum, $numQueryableSeq, $totalSeq);
        print HUBFILE $line, "\n";
    }

    close HUBFILE;
}


sub hubCountSortFn {
    if (not exists $ClusterIdMap->{$a} and not exists $ClusterIdMap->{$b}) {
        return 0;
    } elsif (not exists $ClusterIdMap->{$a}) {
        return 1;
    } elsif (not exists $ClusterIdMap->{$b}) {
        return -1;
    } else {
        return $ClusterIdMap->{$a} <=> $ClusterIdMap->{$b};
    }
}


sub getClusterToIdMapping {
    my $dbh = shift;
    my $util = shift;
    my $ssnSequenceVersion = shift;

    my @clusterNumbers = $util->getClusterNumbers();

    # Get a mapping of IDs to cluster numbers.
    my (%uniref50IdsClusterMap, %uniref90IdsClusterMap, %uniprotIdsClusterMap, %uniprotDomainIdsClusterMap);
    foreach my $clNum (@clusterNumbers) {
        my $nodeIds = $util->getIdsInCluster($clNum, ALL_IDS);
        die "num nodes in cluster 126: " . scalar @$nodeIds if ($debug);
        foreach my $id (@$nodeIds) {
            (my $proteinId = $id) =~ s/:\d+:\d+$//;
            my $sql = "SELECT * FROM uniref WHERE accession = '$proteinId'";
            my $sth = $dbh->prepare($sql);
            $sth->execute;
            while (my $row = $sth->fetchrow_hashref) {
                $uniref50IdsClusterMap{$row->{uniref50_seed}} = $clNum;
                $uniref90IdsClusterMap{$row->{uniref90_seed}} = $clNum;
            }
            $uniprotIdsClusterMap{$proteinId} = $clNum;
            $uniprotDomainIdsClusterMap{$id} = $clNum if $id ne $proteinId;
        }
    }

    # Now reverse the mapping to obtain a mapping of cluster numbers to sequence IDs.
    my (%uniref50ClusterIdsMap, %uniref90ClusterIdsMap, %uniprotIdsMap, %uniprotDomainIdsMap);
    my @iters = (
        [\%uniprotIdsClusterMap, \%uniprotIdsMap],
        [\%uniprotDomainIdsClusterMap, \%uniprotDomainIdsMap],
        [\%uniref50IdsClusterMap, \%uniref50ClusterIdsMap],
        [\%uniref90IdsClusterMap, \%uniref90ClusterIdsMap],
    );
    foreach my $iter (@iters) {
        my $map1 = $iter->[0];
        my $target = $iter->[1];
        foreach my $id (sort keys %$map1) {
            push(@{$target->{$map1->{$id}}}, $id);
        }
    }

    return \%uniprotIdsMap, \%uniprotDomainIdsMap, \%uniref50ClusterIdsMap, \%uniref90ClusterIdsMap;
}


sub saveClusterIdFiles {
    my $uniprotMap = shift;
    my $uniprotDomainMap = shift;
    my $uniref50Map = shift;
    my $uniref90Map = shift;
    my $uniprotIdDir = shift;
    my $uniref50IdDir = shift;
    my $uniref90IdDir = shift;
    my $uniprotSingletonsFile = shift;
    my $uniref50SingletonsFile = shift;
    my $uniref90SingletonsFile = shift;

    my $hasDomain = scalar keys %$uniprotDomainMap;

    my @mappingInfo = (
        [$uniref50Map, "UniRef50", $uniref50IdDir, $uniref50SingletonsFile, 1],
        [$uniref90Map, "UniRef90", $uniref90IdDir, $uniref90SingletonsFile, 1],
    );
    if ($hasDomain) {
        unshift @mappingInfo, [$uniprotMap, "UniProt", $uniprotIdDir, $uniprotSingletonsFile, 0];
        unshift @mappingInfo, [$uniprotDomainMap, "UniProt_Domain", $uniprotIdDir, $uniprotSingletonsFile, 1];
    } else {
        unshift @mappingInfo, [$uniprotMap, "UniProt", $uniprotIdDir, $uniprotSingletonsFile, 1];
    }

    foreach my $info (@mappingInfo) {
        my ($mapping, $filename, $dirPath, $singlesFile, $isDomain) = @$info;
        
        open SINGLES, ">", "$dirPath/singleton_${filename}_IDs.txt";

        foreach my $clNum (sort {$a <=> $b} keys %$mapping) {
            my @accIds = sort @{$mapping->{$clNum}};
            if (scalar @accIds > 1) {
                open FH, ">", "$dirPath/cluster_${filename}_IDs_${clNum}.txt";
                foreach my $accId (@accIds) {
                    print FH "$accId\n";
                }
                close FH;
            } elsif (scalar @accIds == 1) {
                my $accId = $accIds[0];
                print SINGLES "$accId\n";
            }
        }
    }
}


