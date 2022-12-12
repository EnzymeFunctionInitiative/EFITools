#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use List::MoreUtils qw(uniq);
use Getopt::Long;

use EFI::Util::CdHitParser;


my ($cluster, $domain, $annoFile);
my $result = GetOptions(
    "cluster=s"     => \$cluster,
    "struct=s"      => \$annoFile,
    "domain=s"      => \$domain,
);


$domain = "off" if not $domain;

die "Need cluster" if not $cluster or not -f $cluster;
die "Need struct" if not $annoFile;


my $cp = new EFI::Util::CdHitParser();

#parse cluster file to get parent/child sequence associations
open CLUSTER, $cluster or die "cannot open cdhit cluster file $cluster\n";

print "Read in clusters\n";
my $line = "";
while (<CLUSTER>) {
    $line=$_;
    chomp $line;
    $cp->parse_line($line);
}
$cp->finish;

close CLUSTER;


open ANNOTATIONS, ">>$annoFile" or die "cannnot append to annotations file $annoFile\n";
foreach my $clusterId ($cp->get_clusters) {
    my @c = uniq $cp->get_children($clusterId);
    print ANNOTATIONS "$clusterId\n";
    print ANNOTATIONS "\tACC_CDHIT\t", join(",", @c), "\n";
    print ANNOTATIONS "\tACC_CDHIT_COUNT\t", scalar(@c), "\n";
}
close ANNOTATIONS;


