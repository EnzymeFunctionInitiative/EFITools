#!/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use FindBin;
use Scalar::Util qw(looks_like_number);

use lib $FindBin::Bin . "/lib";
use ShortBRED qw(getAbundanceData getClusterSize);


my ($proteinMerged, $clusterMerged, $proteinName, $clusterName, $inputDir, $qDirPattern, $qDirInclude, $clusterListFile);
my $result = GetOptions(
    "merged-protein=s"      => \$proteinMerged,
    "merged-cluster=s"      => \$clusterMerged,
    "protein-name=s"        => \$proteinName,
    "cluster-name=s"        => \$clusterName,
    "input-dir=s"           => \$inputDir,
    "quantify-dir-pat=s"    => \$qDirPattern,
    "force-include=s"       => \$qDirInclude,
    "cluster-list-file=s"   => \$clusterListFile,
);

my $usage = <<USAGE;
$0 -input-dir path_to_input_dir -quantify-dir-pat name_pattern_of_quantify_results_dirs
    -protein-name name_of_protein_abundance_file -cluster-name name-of_cluster_abundance_file
    -merged-protein path_to_merged_protein_abundance_file -merged-cluster path_to_merged_cluster_abundance_file
    -force-includes quantify_dir_to_include_even_if_its_not_completed
    -cluster-list-file path_to_cluster_map_file
USAGE

die $usage if not defined $inputDir or not defined $qDirPattern or
              not defined $proteinMerged or not defined $clusterMerged or
              not defined $clusterName or not defined $proteinName;

$qDirInclude = "" if not defined $qDirInclude;

my $clusterSizes = {};
my $hasClusterSize = 0;
if (defined $clusterListFile and -f $clusterListFile) {
    $clusterSizes = getClusterSizes($clusterListFile);
    $hasClusterSize = length keys %$clusterSizes;
}



my @dirs = glob("$inputDir/$qDirPattern*");

my $allData = {metagenomes => {}, proteins => {}, clusters => {}};

foreach my $dir (@dirs) {
    if (not -f "$dir/job.completed" and not ($qDirInclude and $dir =~ m/$qDirInclude$/)) {
        print "Skipping $dir since it doesn't appear to be completed.\n";
        next; # Skip failed jobs
    }

    my $proteinFile = "$dir/$proteinName";
    my $clusterFile = "$dir/$clusterName";

    my $abData = getAbundanceData($proteinFile, $clusterFile, 0); # Don't remove cluster number from front of protein ID

    foreach my $mgId (@{$abData->{metagenomes}}) {
        $allData->{metagenomes}->{$mgId} = 1;
    }

    foreach my $prot (keys %{$abData->{proteins}}) {
        foreach my $mgId (keys %{$abData->{proteins}->{$prot}}) {
            $allData->{proteins}->{$prot}->{$mgId} = $abData->{proteins}->{$prot}->{$mgId};
        }
    }

    foreach my $clust (keys %{$abData->{clusters}}) {
        foreach my $mgId (keys %{$abData->{clusters}->{$clust}}) {
            $allData->{clusters}->{$clust}->{$mgId} = $abData->{clusters}->{$clust}->{$mgId};
        }
    }
}

my @mgIds = sort keys %{$allData->{metagenomes}};


open PROT, "> $proteinMerged" or die "Unable to write to merged-protein $proteinMerged: $!";

print PROT join("\t", "Cluster", "Protein ID", @mgIds), "\n";

my @prots = sort protSortFn keys %{$allData->{proteins}};

foreach my $prot (@prots) {
    my @res;
    foreach my $mgId (@mgIds) {
        if (exists $allData->{proteins}->{$prot}->{$mgId}) {
            push(@res, $allData->{proteins}->{$prot}->{$mgId});
        } else {
            push(@res, "");
        }
    }

    my ($clusterNum, $protId) = split(m/\|/, $prot);
    print PROT join("\t", $clusterNum, $protId, @res), "\n";
}

close PROT;




open CLUST, "> $clusterMerged" or die "Unable to write to merged-protein $clusterMerged: $!";

my @headers = ("Cluster");
push @headers, "Cluster Size" if $hasClusterSize;
push @headers, @mgIds;
print CLUST join("\t", @headers), "\n";

my @clusters = sort numericSortFn keys %{$allData->{clusters}};

foreach my $cluster (@clusters) {
    my @res;
    foreach my $mgId (@mgIds) {
        if (exists $allData->{clusters}->{$cluster}->{$mgId}) {
            push(@res, $allData->{clusters}->{$cluster}->{$mgId});
        } else {
            push(@res, "");
        }
    }

    my @row = $cluster;
    push @row, (exists $clusterSizes->{$cluster} ? $clusterSizes->{$cluster} : 0) if $hasClusterSize;
    push @row, @res;

    print CLUST join("\t", @row), "\n";
}

close CLUST;





sub protSortFn {
    my ($fta, $pa) = split(m/\|/, $a);
    my ($ftb, $pb) = split(m/\|/, $b);

    if (looks_like_number($fta) and looks_like_number($ftb)) {
        my $comp = $fta <=> $ftb;
        if (not $comp) {
            return $pa cmp $pb;
        } else {
            return $comp;
        }
    } elsif (looks_like_number($fta)) {
        return 1;
    } else {
        return -1;
    }
}


sub numericSortFn {
    if (looks_like_number($a) and looks_like_number($b)) {
        return $a <=> $b;
    } elsif (looks_like_number($a)) {
        return 1;
    } else {
        return -1;
    }
}


