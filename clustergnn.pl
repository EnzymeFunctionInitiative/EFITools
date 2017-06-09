#!/usr/bin/env perl


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
use List::MoreUtils qw{apply uniq any} ;
use XML::LibXML;
use DBD::SQLite;
use DBD::mysql;
use IO;
use XML::Writer;
use File::Slurp;
use XML::LibXML::Reader;
use List::Util qw(sum);
use Array::Utils qw(:all);
use Data::Dumper;

$configfile=read_file($ENV{'EFICFG'}) or die "could not open $ENV{'EFICFG'}\n";
eval $configfile;
$functions=read_file("$FindBin::Bin/gnnfunctions.pl");
eval $functions;

$result = GetOptions(
    "ssnin=s"       => \$ssnin,
    "n=s"           => \$n,
    "nomatch=s"     => \$nomatch,
    "noneigh=s"     => \$noneighfile,
    "gnn=s"         => \$gnn,
    "ssnout=s"      => \$ssnout,
    "incfrac=i"     => \$incfrac,
    "stats=s"       => \$stats,
    "pfam=s"        => \$pfamhubfile
);

$usage="usage $0 -ssnin <filename> -n <positive integer> -nomatch <filename> -gnn <filename> -ssnout <filename>\n-ssnin\t name of original ssn network to process\n-n\t distance (+/-) to search for neighbors\n-nomatch output file that contains sequences without neighbors\n-gnn\t filename of genome neighborhood network output file\n-ssnout\t output filename for colorized sequence similarity network\n";


#error checking on input values

unless(-s $ssnin){
    die "-ssnin $ssnin does not exist or has a zero size\n$usage";
}

unless($n>0){
    die "-n $n must be an integer greater than zero\n$usage";
}

unless($gnn=~/./){
    die "you must specify a gnn output file\n$usage";
}

unless($ssnout=~/./){
    die "you must specify a ssn output file\n$usage";
}

unless($nomatch=~/./){
    die "you must specify and output file for nomatches\n$usage";
}

unless($noneighfile=~/./){
    die "you must specify and output file for noneigh\n$usage";
}

unless($pfamhubfile=~/./){
    die "you must specify and output file for the pfam hub gnn\n$usage";
}

if($incfrac=~/^\d+$/){
    $incfrac=$incfrac/100;
}else{
    if(defined $incfrac){
        die "incfrac must be an integer\n";
    }
    $incfrac=0.20;  
}

if($stats=~/\w+/){
    open STATS, ">$stats" or die "could not write to $stats\n";
    print STATS "Cluster_Number\tPFAM\tPFAM_Description\tCluster_Fraction\tAvg_Distance\tSSN_Cluster_Size\n";
}else{
    open STATS, ">/dev/null" or die "could nto dump stats info to dev null\n";
}

%nodehash=();
%constellations=();
%supernodes=();
%pfams=();
%colors=%{getcolors($dbh)};
%accessioncolors=();
%nodenames=();
%numbermatch=();
%withneighbors=();


#nodehash correlates accessions in a node to the labeled accession of a node, this is for drilling down into repnode networks
#nodehash key is an accession
#constellations maps accessions to a supernode number
#constellations key is an accession
#supernodes is a hash of arrays that contain all of the accessions within a constellation
#key for supernodes are the intergers from %constellations
#pfams contains all of the information for the gnn networks related to sequence (non meta data) including distance
#key for pams is a pfam number.
#colors is a hash where the keys are integers and the values are hexidecimal numbers for colors
#accessioncolors holds the colors assigned by the constellation number for an accession node
#nodenames maps the id from nodes to accession number, this allows you to run this script on cytoscape xgmml exports

#open(GNN,">$gnn") or die "could not write to gnn output file\n";

print "read xgmml file, get list of nodes and edges\n";

$reader=XML::LibXML::Reader->new(location => $ssnin);
(my $title, my $nodes, my $edges)=getNodesAndEdges($reader);

$output=new IO::File(">$ssnout");
$writer=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $output);

$gnnoutput=new IO::File(">$gnn");
$gnnwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $gnnoutput);

$pfamoutput=new IO::File(">$pfamhubfile");
$pfamwriter=new XML::Writer(DATA_MODE => 'true', DATA_INDENT => 2, OUTPUT => $pfamoutput);

print "found ".scalar @{$nodes}." nodes\n";
print "found ".scalar @{$edges}." edges\n";
print "graph name is $title\n";

($nodehash,$nodenames)=getNodes($nodes);

($supernodes, $constellations)=getClusters($nodehash, $nodenames, $edges);

print "find neighbors\n\n";

#gather neighbors of each supernode and store in the $pfams data structure
open( $nomatch_fh, ">$nomatch" ) or die "cannot write file of non-matching accessions\n";
open( $noneighfile_fh, ">$noneighfile") or die "cannot write file of accessions without neighbors\n";

($numbermatch, $clusterNodes, $withneighbors)=getClusterHubData($supernodes, $dbh, $n, $nomatch_fh, $noneighfile_fh);

print "Writing Cluster Hub GNN\n";
writeClusterHubGnn($gnnwriter, $clusterNodes, $withneighbors, $incfrac, $numbermatch, $supernodes);

print "Writing Pfam Hub GNN\n";
writePfamHubGnn($pfamwriter, $clusterNodes, $withneighbors, $incfrac, $numbermatch, $supernodes, $dbh, \%colors);

print "write out colored ssn network ".scalar @{$nodes}." nodes and ".scalar @{$edges}." edges\n";
writeColorSsn($nodes, $edges, $title, $writer, \%colors, $numbermatch, $constellations,$nodenames);
print "$0 finished\n";

