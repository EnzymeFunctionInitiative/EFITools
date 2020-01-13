#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin . "/../../lib";

use Getopt::Long;

use EFI::CGFP::Util qw(getClusterMap);
use EFI::Util::CdHitParser;


my ($cdhitInput, $tableOutput, $clusterMapFile, $colorFile);


my $result = GetOptions(
    "cdhit-file=s"      => \$cdhitInput,
    "table-file=s"      => \$tableOutput,
    "cluster-map=s"     => \$clusterMapFile,
    "color-file=s"      => \$colorFile,
);

my $usage =
"$0 -cdhit-file path_to_input_cdhit_file -table-file path_to_output_table [-color-file path_to_input_colors_file]
";

die "$usage\n-cdhit-file not provided" if not defined $cdhitInput or not -f $cdhitInput;
die "$usage\n-table-file not provided" if not defined $tableOutput or not $tableOutput;
die "$usage\n-cluster-map not provided" if not defined $clusterMapFile or not -f $clusterMapFile;

my $colors = {};
if (defined $colorFile and -f $colorFile) {
    $colors = getColors($colorFile);
}

my $clusterMap = getClusterMap($clusterMapFile);


my $parser = new EFI::Util::CdHitParser();
$parser->parse_file($cdhitInput);
my @clusters = $parser->get_clusters();

open OUTPUT, "> $tableOutput" or die "Unable to open table output $tableOutput: $!";

my @headers = ("Cluster Number", "CD-HIT Seed Sequence", "Protein");
push(@headers, "CD-HIT Seed Sequence Color (If has a Marker)") if keys %$colors;
print OUTPUT join("\t", @headers), "\n";

my $c = 1;
foreach my $cluster (@clusters) {
    my @children = $parser->get_children($cluster);
    my $color = exists $colors->{$c} ? $colors->{$c} : "";
    $c++;
    foreach my $child (@children) {
        my $clusterNum = exists $clusterMap->{$child} ? $clusterMap->{$child} : "N/A";
        my @vals = ($clusterNum, $cluster, $child);
        push(@vals, $color) if keys %$colors;
        print OUTPUT join("\t", @vals), "\n";
    }
}

close OUTPUT;




sub getColors {
    my $file = shift;

    my $colors = {};

    open FILE, $file or warn "Unable to open color file $file: $!";

    while (<FILE>) {
        chomp;
        my ($num, $color) = split(m/\t/);
        $colors->{$num} = $color;
    }

    close FILE;

    return $colors;
}


