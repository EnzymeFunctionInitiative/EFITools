#!/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use FindBin;
use File::Temp;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/lib";

use Setup;


# This line precedes the target lib.
my $test = new Setup(getArgs());

use EFI::Job::EST::Generate::BLAST;
my $jobBuilder = new EFI::Job::EST::Generate::BLAST();

$test->runTest($jobBuilder);



sub getArgs {
    my @a = (
        "blast",
        "--blast-input-id", "zINPUT",
        "--sequence", "MSTAVSFHSQFLGNNPFYQEADYESKLKADFNVEKALPIAFQESLIHKIGRIAFYIFSIIVFPIGIFNFIHWVGGKFIVRSSSPTKMGCSADHAYQLRKRFDPKEKWKVKRFSLPIDEAGTKIDVSIVGRIETLANKRWLINCDGNQSFYENTLQQFNKDNISRKDFKRLLKLTDSNAILFNYPDVGASEGSGRKDLEKAYKTILNFVESDKGLDAEEVISFHTSLGGGVKAAIVEEHEFKPSKKYVYVENQVFDTLSNAIGDHVSRLLQPISHLFFWDMDAVKGSKSLKVPEIILQRGDVSQYTEIHDSEKILGDGLVSKTNNLAKRLLDDPTVDRTKKKFIATNEDHGKELKEPEFLAKQILSFL",
        "--db-type", "uniref50",
        "--pfam", "PF05677",
        "--uniref-version", "uniref50",
    );

    return @a;
}




