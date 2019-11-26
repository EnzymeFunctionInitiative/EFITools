#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;

use EFI::Database;


my $configFile = "$FindBin::Bin/../conf/efi.conf";

die "Config file $configFile does not exist\n" if not -f $configFile;

my $db = new EFI::Database(config_file_path => $configFile);

my @fams = map { s/[^A-Za-z0-9]//g; split m/,/, uc } @ARGV;


my $dbh = $db->getHandle();
die "No database" if not $dbh;

my ($maxf, $maxup, $maxu5, $maxu9) = (6, 7, 8, 8);
my ($totalup, $totalu5, $totalu9) = (0, 0, 0);

my $data = {};

foreach my $fam (@fams) {
    my $sql = "SELECT num_members, num_uniref50_members, num_uniref90_members FROM family_info WHERE family = '$fam'";
    my $sth = $dbh->prepare($sql);
    die "No sth" if not $sth;
    $sth->execute;

    my $row = $sth->fetchrow_hashref;
    next if not $row;

    $maxf = length $fam if length $fam > $maxf;

    $totalup += $row->{num_members};
    $totalu5 += $row->{num_uniref50_members};
    $totalu9 += $row->{num_uniref90_members};

    $data->{$fam} = {
        uniprot => $row->{num_members},
        uniref50 => $row->{num_uniref50_members},
        uniref90 => $row->{num_uniref90_members},
    };
}


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

