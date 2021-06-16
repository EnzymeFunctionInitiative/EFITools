#!/bin/env perl

use strict;
use warnings;


my $f1 = $ARGV[0];
my $f2 = $ARGV[1];
my $colIdx = $ARGV[2] // -1;

my %f1;
my %f2;

open F1, $f1;
while (<F1>) {
    chomp;
    my (@parts) = split(m/\t/);
    $f1{$parts[$colIdx]}++;
}
close F1;


open F2, $f2;
while (<F2>) {
    chomp;
    my (@parts) = split(m/\t/);
    $f2{$parts[$colIdx]}++;
}
close F2;



print "Common:\n";
foreach my $id (sort keys %f1) {
    my $dup = ($f1{$id} // 0) > 1 ? " dup=".$f1{$id} : (($f2{$id} // 0) > 1 ? " dup=".$f2{$id} : "");
    print "    $id$dup\n" if exists $f2{$id};
}

print "Only in $f1:\n";
foreach my $id (sort keys %f1) {
    my $dup = ($f2{$id} // 0) > 1 ? " dup=".$f2{$id} : "";
    print "    $id\n" if not exists $f2{$id};
}

print "Only in $f2:\n";
foreach my $id (sort keys %f2) {
    my $dup = ($f1{$id} // 0) > 1 ? " dup=".$f1{$id} : "";
    print "    $id\n" if not exists $f1{$id};
}





