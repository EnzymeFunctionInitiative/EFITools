#!/usr/bin/env perl

use strict;

my ($enaVer, $ipVer, $upVer) = ("n/a", "n/a", "n/a");

if (exists $ENV{EFI_DB_VERSION_PATH} and -f $ENV{EFI_DB_VERSION_PATH}) {
    open VER, $ENV{EFI_DB_VERSION_PATH};
    while (<VER>) {
        chomp;
        my ($key, $val) = split(m/\t/);
        if ($key and $val) {
            $key = lc $key;
            if ($key eq "ena_version") {
                $enaVer = $val;
            } elsif ($key eq "interpro_version") {
                $ipVer = $val;
            } elsif ($key eq "uniprot_version") {
                $upVer = $val;
            }
        }
    }
    close VER;
}

print "ENA_Version\t$enaVer\n";
print "INTERPRO_Version\t$ipVer\n";
print "UniProt_Version\t$upVer\n";

