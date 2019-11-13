#!/usr/bin/env perl

#program to re-add sequences removed by initial cdhit

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Long;

use EFI::Util::CdHitParser;


my ($cluster, $blastin, $blastout);
my $result = GetOptions(
    "cluster=s"     => \$cluster,
    "blastin=s"     => \$blastin,
    "blastout=s"    => \$blastout
);

die "Need cluster" if not $cluster or not -f $cluster;
die "Need blastin" if not $blastin or not -f $blastin;
die "Need blastout" if not $blastout;


#parse cluster file to get parent/child sequence associations

#create new 1.out file from input 1.out that populates associations

open CLUSTER, $cluster or die "cannot open cdhit cluster file $cluster\n";
open BLASTIN, $blastin or die "cannot open blast input file $blastin\n";
open BLASTOUT, ">$blastout" or die "cannnot write to blast output file $blastout\n";

my $cp = new EFI::Util::CdHitParser(verbose => 1);

#%tree=();

#parse the clstr file
print "Read in clusters\n";
my $line = "";
while (<CLUSTER>) {
    $line=$_;
    chomp $line;
    $cp->parse_line($line);
}

$cp->finish;

print "Demultiplex blast\n";
#read BLASTIN and expand with clusters from cluster file to create demultiplexed file
while (my $line = <BLASTIN>) {
    chomp $line;
    my @lineary=split /\s+/, $line;
    my $linesource=shift @lineary;
    my $linetarget=shift @lineary;
    #print "$linesource\t$linetarget\n";
    if (not $cp->child_exists($linesource)) {
        print "SOURCE $linesource does not exist in the cluster file\n";
        next;
    }
    my @srcChildren = $cp->get_children($linesource);
    if ($linesource eq $linetarget) {
        for (my $i=0; $i < scalar @srcChildren; $i++) {
            for (my $j = $i+1; $j < scalar @srcChildren; $j++) {
                print BLASTOUT join("\t", $srcChildren[$i], $srcChildren[$j], @lineary), "\n";
            }
        }
    } else {
        foreach my $source (@srcChildren) {
            if (not $cp->child_exists($linetarget)) {
                print "TARGET $linetarget does not exist in the cluster file\n";
                next;
            }
            my @targetChildren = $cp->get_children($linetarget);
            foreach my $target (@targetChildren) {
                print BLASTOUT join("\t", $source, $target, @lineary), "\n";
            }
        }
    }
}

