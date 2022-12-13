#!/bin/env perl

use strict;
use warnings;

use Getopt::Long;


my ($mergedFile, @files);
my $result = GetOptions(
    "merged-file=s"     => \$mergedFile,
    "file=s"            => \@files,
);


die "Need merged-file" if not $mergedFile;
die "Need files" if not scalar @files;


my %data;
my @header;

foreach my $fileInfo (@files) {
    my ($cons, $file) = split(m/=/, $fileInfo);

    open my $fh, $file or die "Unable to read $file: $!";
    chomp(my $header = scalar <$fh>); # discard first line
    if (not scalar @header) {
        @header = split(m/\t/, $header);
        splice(@header, 1, 0, "Cons%");
    }

    while (<$fh>) {
        chomp;
        my ($cluster, @stuff) = split(m/\t/);
        unshift @stuff, $cons;
        push @{$data{$cluster}}, \@stuff;
    }

    close $fh;
}


my @clusterNumbers = sort { $a <=> $b } keys %data;

open my $outFh, ">", $mergedFile or die "Unable to write to $mergedFile: $!";

print $outFh join("\t", @header), "\n";
foreach my $num (@clusterNumbers) {
    foreach my $row (@{$data{$num}}) {
        print $outFh join("\t", $num, @{$row}), "\n";
    }
}

close $outFh;


