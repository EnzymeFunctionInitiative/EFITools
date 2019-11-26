

package EFI::Util::BLAST;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../";

use EFI::Annotations;

use constant INPUT_SEQ_ID => "zINPUTSEQ";


sub save_input_sequence {
    my $filePath = shift;
    my $sequence = shift;
    my $seqId = shift || INPUT_SEQ_ID;

    open(QUERY, ">$filePath") or die "Cannot write out Query File to \n";
    print QUERY ">$seqId\n$sequence\n";
    close QUERY;
}


sub write_input_sequence_metadata {
    my $fh = shift;
    my $sequence = shift;
    my $seqId = shift || INPUT_SEQ_ID;

    my $seqLength = length $sequence;

    print $fh "$seqId\n";
    print $fh "\tDescription\tInput Sequence\n";
    print $fh "\tSequence_Length\t$seqLength\n";
    print $fh "\t" . EFI::Annotations::FIELD_SEQ_SRC_KEY . "\t" . EFI::Annotations::FIELD_SEQ_SRC_VALUE_INPUT . "\n";
}


1;

