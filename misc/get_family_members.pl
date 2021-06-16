#!/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use FindBin;
use lib "$FindBin::Bin/../lib";
use EFI::Database;
use Getopt::Long;
use List::MoreUtils qw{uniq};

$| = 1;

my ($configFile, $family, $unique, $statsOnly, $allClans, $noFrag, $doOverlap, $includeFam);

GetOptions(
    "config=s"          => \$configFile,
    "family=s"          => \$family,
    "unique"            => \$unique,
    "stats-only"        => \$statsOnly,
    "all-clans"         => \$allClans,
    "overlap-stats"     => \$doOverlap,
    "no-frag"           => \$noFrag,
    "include-fam"       => \$includeFam,
);

$unique = 0 if not defined $unique;
$allClans = 0 if not defined $allClans;
$family = "" if not defined $family;

if (not $configFile or not -f $configFile and exists $ENV{EFI_CONFIG}) {
    $configFile = $ENV{EFI_CONFIG};
}

die "Invalid arguments given: no config file.\n" . help() unless (defined $configFile and -f $configFile);
die "Invalid arguments given: no family.\n" . help() if (not $family and not $allClans);


my $db = new EFI::Database(config_file_path => $configFile);
my $dbh = $db->getHandle();

my @args = split(/,/, $family);


if ($allClans) {
    #print "Retrieving data for all clans will take a long time.  Are you sure? ";
    #exit if (scalar <STDIN> !~ /y/i);
    @args = retrieveAllClans();
    print "Number of Clans\t", scalar(@args), "\n";
    print join("\t", "Clan", "#Fams", "Total # IDs", "Unique # IDs"), "\n";
}

my @families; # Any families that are specified on the command line that are not part of the clans

# Check for and get the families in the specified clan(s)
foreach my $item (@args) {
    if ($item =~ /^cl/i) {
        my @fams = retrieveFamiliesForClan($item);

        my @accIds;
        foreach my $fam (@fams) {
            my @ids = retrieveForFamily($fam, "PFAM");
            print join("\t", "Family", $fam, scalar @ids), "\n" if not $allClans;
            push(@accIds, @ids);
        }

        if ($allClans) {
            my @uniqueAccIds = uniq @accIds;
            print join("\t", $item, scalar(@fams), scalar(@accIds), scalar(@uniqueAccIds)), "\n";
        }
    } else {
        push(@families, $item);
    }
}

$dbh->disconnect() and exit if $allClans;


my %idfMap;
my %fidMap;
my @accIds;
foreach my $fam (@families) {
    my $table = "";
    $table = "PFAM" if $fam =~ /^pf/i;
    $table = "INTERPRO" if $fam =~ /^ip/i;
    warn "Invalid family given" if not $table;

    my @ids = retrieveForFamily($fam, $table);
    @ids = uniq @ids;
    #print join("\t", $fam, scalar @ids), "\n";
    map { push @{$idfMap{$_}}, $fam } @ids;
    $fidMap{$fam} = [@ids];
    push(@accIds, @ids);
}

$dbh->disconnect();

print "Total IDs\t", scalar @accIds, "\n" if not $doOverlap;

my $numUnique = -1;
if ($unique) {
    my @uniqueAccIds = uniq @accIds;
    $numUnique = scalar @accIds - scalar @uniqueAccIds;
    @accIds = @uniqueAccIds;
    print "Unique IDs\t", scalar @uniqueAccIds, "\n";
}


if ($doOverlap) {
    my %overlap;
    foreach my $fam (keys %fidMap) {
        my $numOver = 0;
        my $numId = scalar @{ $fidMap{$fam} };
        foreach my $id (@{ $fidMap{$fam} }) {
            $numOver++ if scalar @{$idfMap{$id}} > 1;
#            print join("\t", $fam, $id, join(",", @{$idfMap{$id}})), "\n";
        }
        #$overlap{$fam} = $numOver / $numId;
        $overlap{$fam} = int(100000 * $numOver / $numId + 0.5) / 1000;
    }
    print join("\t", "Family", "Percent Overlap"), "\n";
    foreach my $fam (sort keys %overlap) {
        print join("\t", $fam, $overlap{$fam}), "\n";
    }
} elsif (not $statsOnly) {
    foreach my $id (@accIds) {
        print $id, "\n";
    }
}









sub retrieveAllClans {
    my $sql = "select distinct clan_id from PFAM_clans where clan_id != '' order by clan_id";
    my $sth = $dbh->prepare($sql);
    $sth->execute;

    my @clans;
    while (my $row = $sth->fetchrow_arrayref) {
        push @clans, $row->[0];
    }

    return @clans;
}

sub retrieveFamiliesForClan {
    my ($clan, $table) = @_;

    my $sql = "select pfam_id from PFAM_clans where clan_id = '$clan'";
    my $sth = $dbh->prepare($sql);
    $sth->execute;

    my @fams;
    while (my $row = $sth->fetchrow_arrayref) {
        push @fams, $row->[0];
    }

    return @fams;
}

sub retrieveForFamily {
    my ($family, $table) = @_;

    my $fragJoin = $noFrag ? "JOIN annotations ON $table.accession = annotations.accession" : "";
    my $fragWhere = $noFrag ? "AND annotations.Fragment = 0" : "";

    my $sql = "select $table.accession from $table $fragJoin where $table.id = '$family' $fragWhere";
    my $sth = $dbh->prepare($sql);
    $sth->execute;

    my @ids;
    while (my $row = $sth->fetchrow_arrayref) {
        #print $row->[0], "\n";
        push @ids, $row->[0];
    }

    return @ids;
}


sub help {
    return <<HELP;
Usage: $0 --family=family_list [--unique --config=config_file_path]

    --family        one or more comma-separated families or Pfam clans
    --unique        output a unique list of accession IDs (accession IDs may be in multiple families)
    --stats-only    only output the statistics, don't output the accession IDs

HELP
    ;
}


