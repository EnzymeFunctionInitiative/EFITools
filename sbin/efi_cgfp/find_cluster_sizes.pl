#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin . "/../../lib";

use Getopt::Long;

use EFI::CGFP::Util qw(getClusterSizes);


my ($clusterListFile, $outputFile);
my $result = GetOptions(
    "output-file=s"         => \$outputFile,
    "cluster-list-file=s"   => \$clusterListFile,
);

my $usage = <<USAGE;
$0 -output-file path_to_output_size_file
    -cluster-list-file path_to_cluster_map_file
USAGE

die $usage if not defined $clusterListFile or not -f $clusterListFile or not defined $outputFile;


my $clusterSizes = {};
$clusterSizes = getClusterSizes($clusterListFile);

my @clusters = sort
    {
        my $res = $clusterSizes->{$b} <=> $clusterSizes->{$a};
        if (not $res) {
            return $a cmp $b;
        } else {
            return $res;
        }
    } keys %$clusterSizes;

open OUTPUT, ">$outputFile" or die "Unable to open output cluster size file $outputFile: $!";

foreach my $cluster (@clusters) {
    print OUTPUT "$cluster\t", $clusterSizes->{$cluster}, "\n";
}

close OUTPUT;

