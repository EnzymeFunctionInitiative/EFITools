#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


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


use FindBin;
use Getopt::Long;
use XML::LibXML;
use DBD::mysql;
use IO;
use XML::Writer;
use XML::LibXML::Reader;

use lib $FindBin::Bin . "/lib";
#use lib $ENV{EFIEST} . "/lib";
use EFI::Database;
use EFI::GNN;


#$configfile=read_file($ENV{'EFICFG'}) or die "could not open $ENV{'EFICFG'}\n";
#eval $configfile;
#$functions=read_file("$FindBin::Bin/gnnfunctions.pl");
#eval $functions;

$result = GetOptions(
    "ssnin=s"           => \$ssnin,
    "n|nb-size=s"       => \$n,
#    "nomatch=s"         => \$nomatch,
#    "noneigh=s"         => \$noneighfile,
    "warning-file=s"    => \$warningFile,
    "gnn=s"             => \$gnn,
    "ssnout=s"          => \$ssnout,
    "incfrac|cooc=i"    => \$incfrac,
    "stats=s"           => \$stats,
    "pfam=s"            => \$pfamhubfile,
    "config=s"          => \$configFile,
    "pfam-dir=s"        => \$pfamDir,
    "pfam-zip=s"        => \$pfamZip, # only used for GNT calls, non batch
    "id-dir=s"          => \$idDir,
    "id-zip=s"          => \$idZip, # only used for GNT calls, non batch
    "none-dir=s"        => \$noneDir,
    "none-zip=s"        => \$noneZip, # only used for GNT calls, non batch
    "id-out=s"          => \$idOutputFile,
    "disable-nnm"       => \$dontUseNewNeighborMethod,
);

$usage = <<USAGE
usage: $0 -ssnin <filename> -n <positive integer> -nomatch <filename> -gnn <filename> -ssnout <filename>
    -ssnin          name of original ssn network to process
    -nb-size        distance (+/-) to search for neighbors
    -gnn            filename of genome neighborhood network output file
    -ssnout         output filename for colorized sequence similarity network
    -warning-file   output file that contains sequences without neighbors or matches
    -cooc           co-occurrence
    -stats          file to output tabular statistics to
    -pfam           file to output PFAM hub GNN to
    -id-dir         path to directory to output lists of IDs (one file/list per cluster number)
    -id-zip         path to a file to zip all of the output lists
    -pfam-dir       path to directory to output PFAM cluster data (one file/list per cluster number)
    -pfam-zip       path to a file to output zip file for PFAM cluster data
    -id-out         path to a file to save the ID, cluster #, cluster color
    -config         configuration file for database info, etc.
USAGE
;
#    -nomatch        output file that contains sequences without neighbors
#    -noneigh        output file that contains sequences without neighbors


$batchMode = 0 if not defined $batchMode;

if (not -f $configFile and not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
} elsif (not -f $configFile) {
    $configFile = $ENV{EFICONFIG};
}

#error checking on input values

unless(-s $ssnin){
    die "-ssnin $ssnin does not exist or has a zero size\n$usage";
}

unless($n>0){
    die "-nb-size $n must be an integer greater than zero\n$usage";
}

#unless($gnn=~/./){
#    die "you must specify a gnn output file\n$usage";
#}

#unless($ssnout=~/./){
#    die "you must specify a ssn output file\n$usage";
#}

#unless($nomatch=~/./){
#    die "you must specify and output file for nomatches\n$usage";
#}

#unless($noneighfile=~/./){
#    die "you must specify and output file for noneigh\n$usage";
#}

#unless($pfamhubfile=~/./){
#    die "you must specify and output file for the pfam hub gnn\n$usage";
#}

if($incfrac=~/^\d+$/){
    $incfrac=$incfrac/100;
}else{
    if(defined $incfrac){
        die "incfrac must be an integer\n";
    }
    $incfrac=0.20;  
}

if (not defined $dontUseNewNeighborMethod) {
    $useNewNeighborMethod = 1;
} else {
    $useNewNeighborMethod = 0;
}

my $colorOnly = ($ssnout and not $gnn and not $pfamhubfile) ? 1 : 0;

my $db = new EFI::Database(config_file_path => $configFile);
my $dbh = $db->getHandle();

mkdir $pfamDir  or die "Unable to create $pfamDir: $!"  if $pfamDir and not -d $pfamDir;
mkdir $idDir    or die "Unable to create $idDir: $!"    if $idDir and not -d $idDir;
mkdir $noneDir  or die "Unable to create $noneDir: $!"  if $noneDir and not -d $noneDir;

my %gnnArgs = (dbh => $dbh, incfrac => $incfrac, use_nnm => $useNewNeighborMethod, color_only => $colorOnly);
$gnnArgs{pfam_dir} = $pfamDir if $pfamDir and -d $pfamDir;
$gnnArgs{id_dir} = $idDir if $idDir and -d $idDir;

my $util = new EFI::GNN(%gnnArgs);

if($stats=~/\w+/){
    open STATS, ">$stats" or die "could not write to $stats\n";
    print STATS "Cluster_Number\tPFAM\tPFAM_Description\tCluster_Fraction\tAvg_Distance\tSSN_Cluster_Size\n";
}else{
    open STATS, ">/dev/null" or die "could nto dump stats info to dev null\n";
}

%nodehash=();
%constellations=();
%supernodes=();
%nodenames=();
%numbermatch=();
%withneighbors=();


#nodehash correlates accessions in a node to the labeled accession of a node, this is for drilling down into repnode networks
#nodehash key is an accession
#constellations maps accessions to a supernode number
#constellations key is an accession
#supernodes is a hash of arrays that contain all of the accessions within a constellation
#key for supernodes are the intergers from %constellations
#key for pams is a pfam number.
#nodenames maps the id from nodes to accession number, this allows you to run this script on cytoscape xgmml exports

print "read xgmml file, get list of nodes and edges\n";

$reader=XML::LibXML::Reader->new(location => $ssnin);
my ($title, $nodes, $edges, $nodeMap) = $util->getNodesAndEdges($reader);


print "found ".scalar @{$nodes}." nodes\n";
print "found ".scalar @{$edges}." edges\n";
print "graph name is $title\n";

my ($nodehash, $nodenames) = $util->getNodes($nodes);

#my $includeSingletonsInSsn = (not defined $gnn or not length $gnn) and (not defined $pfamhubfile or not length $pfamhubfile);
# We include singletons by default, although if they don't have any represented nodes they won't be colored in the SSN.
my $includeSingletons = 1;
my ($supernodes, $constellations, $singletons) = $util->getClusters($nodehash, $nodenames, $edges, $nodeMap, $includeSingletons);

print "find neighbors\n\n";

if ($gnn and $warningFile) { #$nomatch and $noneighfile) {
    open($warning_fh, ">$warningFile") or die "cannot write file of no-match/no-neighbor warnings for accessions\n";
} else {
    open($warning_fh, ">/dev/null") or die "cannot write file of no-match/no-neighbor warnings to /dev/null\n";
}
print $warning_fh "UniProt ID:No Match/No Neighbor\n";


my $useExistingNumber = $util->hasExistingNumber($nodes);
($numbermatch, $numberOrder) = $util->numberClusters($supernodes, $useExistingNumber);

my $gnnData = {};
if (not $colorOnly) {
    my $useCircTest = 1;
    ($clusterNodes, $withneighbors, $noMatchMap, $noNeighborMap, $genomeIds, $noneFamily) =
            $util->getClusterHubData($supernodes, $n, $warning_fh, $useCircTest, $numberOrder);

    if ($gnn) {
        print "Writing Cluster Hub GNN\n";
        $gnnoutput=new IO::File(">$gnn");
        $gnnwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $gnnoutput);
        $util->writeClusterHubGnn($gnnwriter, $clusterNodes, $withneighbors, $numbermatch, $supernodes);
    }
    
    if ($pfamhubfile) {
        print "Writing Pfam Hub GNN\n";
        $pfamoutput=new IO::File(">$pfamhubfile");
        $pfamwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $pfamoutput);
        $util->writePfamHubGnn($pfamwriter, $clusterNodes, $withneighbors, $numbermatch, $supernodes);
        $util->writePfamNoneClusters($noneDir, $noneFamily, $numbermatch);
    }
    
    $gnnData->{noMatchMap} = $noMatchMap;
    $gnnData->{noNeighborMap} = $noNeighborMap;
    $gnnData->{genomeIds} = $genomeIds;
}

if ($ssnout) {
    print "write out colored ssn network ".scalar @{$nodes}." nodes and ".scalar @{$edges}." edges\n";
    $output=new IO::File(">$ssnout");
    $writer=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $output);

    $util->writeColorSsn($nodes, $edges, $title, $writer, $numbermatch, $constellations, $nodenames, $supernodes, $gnnData);
}

close($warning_fh);

#$util->writePfamQueryData($numbermatch, $supernodes, $clusterNodes) if $dataDir;
$util->writeIdMapping($idOutputFile, $numbermatch, $constellations, $supernodes) if $idOutputFile;
$util->closeClusterMapFiles() if $dataDir;
$util->finish();

`zip -j $ssnout.zip $ssnout` if $ssnout;
`zip -j $gnn.zip $gnn` if not $colorOnly and $gnn;
`zip -j $pfamhubfile.zip $pfamhubfile` if not $colorOnly and $pfamhubfile;
`zip -j -r $pfamZip $pfamDir` if $pfamZip and $pfamDir;
`zip -j -r $idZip $idDir` if $idZip and $idDir;
`zip -j -r $noneZip $noneDir` if $noneZip and $noneDir;


print "$0 finished\n";

