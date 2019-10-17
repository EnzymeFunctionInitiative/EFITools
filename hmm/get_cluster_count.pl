#!/bin/env perl

use strict;
use warnings;

use Getopt::Long;


my ($sizeFile, $countFile, $minCount);
my $result = GetOptions(
    "size-file=s"       => \$sizeFile,
    "count-file=s"      => \$countFile,
    "min-count=s"       => \$minCount,
);


die "Need size-file" if not $sizeFile or not -f $sizeFile;
die "Need count-file" if not $countFile;

$minCount = 5 if not $minCount;


open SIZE, $sizeFile or die "Unable to open $sizeFile for writing: $!";
scalar <SIZE>; #discard header

open COUNT, ">", $countFile or die "Unable to open $countFile for writing: $!";

while (<SIZE>) {
    chomp;
    my ($clusterNum, @counts) = split(m/\t/);
    if (scalar @counts) {
        if ($counts[$#counts] >= $minCount) {
            print COUNT $clusterNum, "\n";
        }
    }
}

close COUNT;

close SIZE;

