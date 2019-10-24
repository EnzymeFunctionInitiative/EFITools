#!/bin/env perl

use strict;
use warnings;

use Getopt::Long;


my ($sizeFile, $countFile, $minCount, $fastaDir);
my $result = GetOptions(
    "size-file=s"       => \$sizeFile,
    "count-file=s"      => \$countFile,
    "min-count=s"       => \$minCount,
    "fasta-dir=s"       => \$fastaDir,
);


die "Need size-file" if (not $sizeFile or not -f $sizeFile) and not $fastaDir;
die "Need count-file" if not $countFile;

my $hasMinCount = defined $minCount;
$minCount = 5 if not $minCount;

open COUNT, ">", $countFile or die "Unable to open $countFile for writing: $!";
    
if ($fastaDir and -d $fastaDir) {
    my @files = glob("$fastaDir/cluster_*.fasta");
    my @wc = map { my $c = `grep \\> $_ | wc -l`; chomp $c; (my $num = $_) =~ s/^.*cluster_(domain_)?(\d+)\.fasta$/$2/; [$num, $c] } @files;
    map { print COUNT $_->[0], "\n" if $_->[1] >= $minCount; } @wc if $hasMinCount;
    map { print COUNT $_->[0], "\t", $_->[1], "\n"; } @wc if not $hasMinCount;
} else {
    open SIZE, $sizeFile or die "Unable to open $sizeFile for writing: $!";
    scalar <SIZE>; #discard header
    
    while (<SIZE>) {
        chomp;
        my ($clusterNum, @counts) = split(m/\t/);
        if (scalar @counts) {
            if ($counts[$#counts] >= $minCount) {
                print COUNT $clusterNum, "\n";
            }
        }
    }
    
    close SIZE;
}

close COUNT;
    

