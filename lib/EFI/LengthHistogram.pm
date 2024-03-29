
package EFI::LengthHistogram;

use strict;
use warnings;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {len => [], num_seq => 0, incfrac => 0.99};
    bless($self, $class);
    $self->{incfrac} = $args{incfrac} if $args{incfrac};

    return $self;
}


sub addData {
    my $self = shift;
    my $data = shift;

    if (ref $data eq "HASH") {
        foreach my $id (keys %{$data}) {
            foreach my $dom (@{$data->{$id}}) {
                my $len = $dom->{end} - $dom->{start};
                $self->addScalarData($len);
            }
        }
    } else {
        $self->addScalarData($data);
    }
}


sub addScalarData {
    my $self = shift;
    my $len = shift;

    $self->{len}->[$len] = 0 if not defined $self->{len}->[$len];
    $self->{len}->[$len]++;
    $self->{num_seq}++;
}


sub saveToFile {
    my $self = shift;
    my $file = shift;

    my $numSequences = $self->{num_seq};
    my $endTrim = $numSequences * (1 - $self->{incfrac}) / 2;
    $endTrim = int $endTrim;
    
    my ($sequenceSum, $minCount, $count) = (0, 0, 0);
    foreach my $len (@{$self->{len}}) {
        if ($sequenceSum <= ($numSequences - $endTrim)) {
            $count++;
            $sequenceSum += $len if defined $len;
            if ($sequenceSum < $endTrim) {
                $minCount++;
            }
        }
    }

    my $out = *STDOUT;
    my $hasOut = 0;
    if ($file) {
        open $out, ">", $file or die "Unable to open length file $file for writing: $!";
        $hasOut = 1;
    }
    
    for (my $i = $minCount; $i <= $count; $i++) {
        if (defined $self->{len}->[$i]) {
            $out->print("$i\t$self->{len}->[$i]\n");
        } else {
            $out->print("$i\t0\n");
        }
    }
    
    $out->close if $hasOut;;
}


1;

