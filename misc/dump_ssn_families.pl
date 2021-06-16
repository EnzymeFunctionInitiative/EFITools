#!/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use FindBin;
use Data::Dumper;

use lib $FindBin::Bin . "/../lib";
use EFI::SSN::Parser;


my ($ssn, $output);
my $result = GetOptions(
    "input=s"               => \$ssn,
    "output=s"              => \$output,
);

my $usage = <<USAGE;
$0 --input path_to_input_ssn --output path_to_output_file

USAGE

die "$usage\n--input SSN parameter missing" if not defined $ssn or not -f $ssn;
die "$usage\n--output file parameter missing" if not $output;


my $ssn = openSsn($ssnIn);
$ssn->parse;

$ssn->setExtraTitle("Neighborhood Connectivity");
$ssn->registerHandler(NODE_WRITER, \&writeNode);
$ssn->registerHandler(ATTR_FILTER, \&filterAttr);

$ssn->write($ssnOut);










sub writeNode {
    my $nodeId = shift;
    my $childNodeIds = shift;
    my $fieldWriter = shift;
    my $listWriter = shift;

    return if not $mapping->{$nodeId};
    my $d = $mapping->{$nodeId};

    &$fieldWriter($primaryName, "string", $d->{color}) if $primaryName;
    &$fieldWriter($colorName, "string", $d->{color}) if $colorName;

    for (my $ei = 0; $ei <= $#extraCol; $ei++) {
        my $name = $extraCol[$ei]->{name};
        my $val = $d->{extra}->[$ei];
        &$fieldWriter($name, "string", $val);
    }
}


sub parseMappingFile {
    my $file = shift;
    my $nodeCol = shift;
    my $colorCol = shift;
    my $extraCol = shift;

    open my $fh, "<", $file or die "Unable to open mapping file $file: $!";

    my %data;
    while (<$fh>) {
        chomp;
        my @parts = split(m/\t/);
        my $d = {color => $parts[$colorCol], extra => []};
        map { push @{$d->{extra}}, $parts[$_->{col}] } @$extraCol; 
        $data{$parts[$nodeCol]} = $d;
    }

    close $fh;

    return \%data;
}
        

sub parseExtraCol {
    my $colInfo = shift;

    my @info = split(m/;/, $colInfo);

    my @cols;
    foreach my $info (@info) {
        my @p = split(m/\-/, $info);
        next if scalar @p < 2;
        push @cols, {col => $p[0] - 1, name => $p[1]};
    }

    return @cols;
}


sub filterAttr {
    my $id = shift;
    my $attr = shift;
    return ($attr eq "Neighborhood Connectivity" or $attr eq "node.fillColor" or $attr eq "Neighborhood Connectivity Color");
}


