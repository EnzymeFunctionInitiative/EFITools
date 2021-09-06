#!/bin/env perl

use strict;
use warnings;

use FindBin;
use Data::Dumper;

use lib "$FindBin::Bin/../lib";


use EFI::Options;

my $optionParser = new EFI::Options();


my %opts = (
    "string-arg" => "s",
    "number-arg" => "i",
    "flag-arg" => "",
    "array-arg" => "s@",
);


my $optValues = $optionParser->getOptions(\%opts);


print Dumper($optValues);







