#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use EFI::Database;
use EFI::Job::Size qw(family_count);


my $configFile = "$FindBin::Bin/../conf/efi.conf";

die "Config file $configFile does not exist\n" if not -f $configFile;

my $db = new EFI::Database(config_file_path => $configFile);

my @fams = map { split m/,/, uc } @ARGV;

my $maxf = 6;
map { $maxf = length $_ if length $_ > $maxf; } @fams;


my $dbh = $db->getHandle();
die "No database" if not $dbh;


my ($totalup, $totalu5, $totalu9, $data) = family_count($dbh, @fams);


my ($maxup, $maxu5, $maxu9) = (7, 8, 8);
$maxup = length commify($totalup) if length commify($totalup) > $maxup;
$maxu5 = length commify($totalu5) if length commify($totalu5) > $maxu5;
$maxu9 = length commify($totalu9) if length commify($totalu9) > $maxu9;

my $hdr = sprintf "%-${maxf}s  |  %${maxup}s |  %${maxu5}s |  %${maxu9}s ", "Total", "UniProt", "UniRef50", "UniRef90";
print $hdr, "\n";
print "-" x length $hdr, "\n";

foreach my $fam (sort keys %$data) {
    printf "%-${maxf}s  |  %${maxup}s |  %${maxu5}s |  %${maxu9}s \n", $fam,
        commify($data->{$fam}->{uniprot}), commify($data->{$fam}->{uniref50}), commify($data->{$fam}->{uniref90});
}


print "-" x length $hdr, "\n";
printf "%-${maxf}s  |  %${maxup}s |  %${maxu5}s |  %${maxu9}s ", "Total", commify($totalup), commify($totalu5), commify($totalu9);
print "\n";


# Perl cookbook
sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $text
}

