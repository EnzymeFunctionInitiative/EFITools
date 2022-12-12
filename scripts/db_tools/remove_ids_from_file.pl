#!/bin/env perl

use strict;
use warnings;


use Getopt::Long;


my ($inFile, $outFile, $idListFile, $colIdx, $verbose);

my $result = GetOptions(
    "id-list=s"     => \$idListFile,
    "in=s"          => \$inFile,
    "out=s"         => \$outFile,
    "search-col=s"  => \$colIdx,
    "verbose"       => \$verbose,
);

die "-id-list file is required" if not $idListFile or not -f $idListFile;
die "-in file is required" if not $inFile or not -f $inFile;
die "-out file is required" if not $outFile;

$colIdx = 0 if not $colIdx;



my %ids;

open my $idFh, $idListFile or die "Unable to open $idListFile for reading: $!";

while (<$idFh>) {
    chomp;
    $ids{$_} = 1;
}

close $idFh;



open my $inFh, $inFile or die "Unable to open $inFile for reading: $!";
open my $outFh, ">", $outFile or die "Unable to open $outFile for writing: $!";

if ($inFile =~ m/\.fasta/) {
    handleFasta($inFh, $outFh);
} else {
    handleTab($inFh, $outFh);
}

close $outFh;
close $inFh;








sub handleFasta {
    my ($inFh, $outFh) = @_;

    my $writeSeq = 1;

    while (<$inFh>) {
        if (m/^\>.*?([A-Z0-9]+)/) {
            if (not exists $ids{$1}) {
                print "Kept\t$1\n" if $verbose;
                $writeSeq = 1;
            } else {
                print "Removed\t$1\n" if $verbose;
                $writeSeq = 0;
            }
        }
        if ($writeSeq) {
            print $outFh "$_";
        }
    }
}


sub handleTab {
    my ($inFh, $outFh) = @_;

    while (<$inFh>) {
        my @parts = split(m/\t/);
        if (not $parts[$colIdx] or not exists $ids{$parts[$colIdx]}) {
            print $outFh "$_";
        }
    }
}



