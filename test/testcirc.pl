#!/usr/bin/env perl

BEGIN {
    die "Please load efiest2 before runing this script" if not $ENV{EFIEST};
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
use Data::Dumper;

use lib $FindBin::Bin . "/../lib";
use lib $ENV{EFIEST} . "/lib";
use Biocluster::Database;
use Biocluster::GNN;


#$configfile=read_file($ENV{'EFICFG'}) or die "could not open $ENV{'EFICFG'}\n";
#eval $configfile;
#$functions=read_file("$FindBin::Bin/gnnfunctions.pl");
#eval $functions;

$result = GetOptions(
    "n|nb-size=s"       => \$n,
    "incfrac|cooc=i"    => \$incfrac,
    "config=s"          => \$configFile,
    "id=s"              => \$accId,
    "usecirc"           => \$useCircTest
);

$usage = <<USAGE
usage: $0 -ssnin <filename> -n <positive integer> -nomatch <filename> -gnn <filename> -ssnout <filename>
    -nb-size        distance (+/-) to search for neighbors
    -cooc           co-occurrence
    -config         configuration file for database info, etc.
USAGE
;


if (not -f $configFile and not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
} elsif (not -f $configFile) {
    $configFile = $ENV{EFICONFIG};
}

#error checking on input values

$useCircTest = 0 if not defined $useCircTest;

unless($n>0){
    die "-nb-size $n must be an integer greater than zero\n$usage";
}

if($incfrac=~/^\d+$/){
    $incfrac=$incfrac/100;
}else{
    if(defined $incfrac){
        die "incfrac must be an integer\n";
    }
    $incfrac=0.20;  
}

my $db = new Biocluster::Database(config_file_path => $configFile);
my $dbh = $db->getHandle();

my %gnnArgs = (dbh => $dbh, incfrac => $incfrac);
$gnnArgs{data_dir} = $dataDir if $dataDir and -d $dataDir;
my $util = new Biocluster::GNN(%gnnArgs);


#open STATS, ">/dev/null" or die "could nto dump stats info to dev null\n";
#
#%nodehash=();
#%constellations=();
#%supernodes=();
#%nodenames=();
#%numbermatch=();
#%withneighbors=();
#
#
##nodehash correlates accessions in a node to the labeled accession of a node, this is for drilling down into repnode networks
##nodehash key is an accession
##constellations maps accessions to a supernode number
##constellations key is an accession
##supernodes is a hash of arrays that contain all of the accessions within a constellation
##key for supernodes are the intergers from %constellations
##key for pams is a pfam number.
##nodenames maps the id from nodes to accession number, this allows you to run this script on cytoscape xgmml exports
#
#print "read xgmml file, get list of nodes and edges\n";
#
#$reader=XML::LibXML::Reader->new(location => $ssnin);
#(my $title, my $nodes, my $edges) = $util->getNodesAndEdges($reader);
#
#
#print "found ".scalar @{$nodes}." nodes\n";
#print "found ".scalar @{$edges}." edges\n";
#print "graph name is $title\n";
#
#($nodehash,$nodenames) = $util->getNodes($nodes);
#
#($supernodes, $constellations) = $util->getClusters($nodehash, $nodenames, $edges);
#
#print "find neighbors\n\n";
#
#if ($gnn and $nomatch and $noneighfile) {
#    open( $nomatch_fh, ">$nomatch" ) or die "cannot write file of non-matching accessions\n";
#    open( $noneighfile_fh, ">$noneighfile") or die "cannot write file of accessions without neighbors\n";
#} else {
#    open( $nomatch_fh, ">/dev/null" ) or die "cannot write non-matching accessions to /dev/null\n";
#    open( $noneighfile_fh, ">/dev/null") or die "cannot write accessions without neighbors to /dev/null\n";
#}

$Data::Dumper::Indent = 1;

open( $nomatch_fh, ">/dev/null" ) or die "cannot write non-matching accessions to /dev/null\n";
open( $noneighfile_fh, ">/dev/null") or die "cannot write accessions without neighbors to /dev/null\n";

my $pfam = $util->findNeighbors($accId, $n, $nomatch_fh, $noneighfile_gh, $useCircTest);
print Dumper($pfam);

#print join("\n", map { "$_ => " . $pfam->{$_} } keys %$pfam), "\n";

#($numbermatch, $clusterNodes, $withneighbors) = $util->getClusterHubData($supernodes, $n, $nomatch_fh, $noneighfile_fh);
#
#if ($gnn) {
#    print "Writing Cluster Hub GNN\n";
#    $gnnoutput=new IO::File(">$gnn");
#    $gnnwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $gnnoutput);
#    $util->writeClusterHubGnn($gnnwriter, $clusterNodes, $withneighbors, $numbermatch, $supernodes);
#}
#
#if ($pfamhubfile) {
#    print "Writing Pfam Hub GNN\n";
#    $pfamoutput=new IO::File(">$pfamhubfile");
#    $pfamwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $pfamoutput);
#    $util->writePfamHubGnn($pfamwriter, $clusterNodes, $withneighbors, $numbermatch, $supernodes);
#}
#
#if ($ssnout) {
#    print "write out colored ssn network ".scalar @{$nodes}." nodes and ".scalar @{$edges}." edges\n";
#    $output=new IO::File(">$ssnout");
#    $writer=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $output);
#    $util->writeColorSsn($nodes, $edges, $title, $writer, $numbermatch, $constellations, $nodenames, $supernodes);
#}

close($nomatch_fh);
close($noneighfile_fh);

#$util->writeIdMapping($idOutputFile, $numbermatch, $constellations) if $idOutputFile;
#$util->closeClusterMapFiles() if $dataDir;

print "$0 finished\n";

