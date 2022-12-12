#!/bin/env perl

use warnings;
use strict;

use FindBin;
use Getopt::Long;
use lib $FindBin::Bin . "/lib";

use EFI::GNN::Arrows;


my ($dbFile, $checkVersion, $versionFile);
my $result = GetOptions(
    "db-file=s"             => \$dbFile,
    "version=i"             => \$checkVersion,
    "version-file=s"        => \$versionFile,
);

die "Need a db-file" if not $dbFile and not -f $dbFile;
die "Need a version" if not $checkVersion;


my $dbVersion = EFI::GNN::Arrows::getDbVersion($dbFile);

if ($dbVersion >= $checkVersion) {
    if ($versionFile) {
        open FILE, ">", $versionFile;
        print FILE $dbVersion;
        close FILE;
    }
}

print "Check Version: $checkVersion\nDb File Version: $dbVersion\n";

