
package EFI::Util;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(getLmod checkNetworkType computeRamReservation);


sub getLmod {
    my ($pattern, $default) = @_;

    use Capture::Tiny qw(capture);

    my ($out, $err) = capture {
        `source /etc/profile; module -t avail`;
    };
    my @py2 = grep m{$pattern}, (split m/[\n\r]+/s, $err);

    return scalar @py2 ? $py2[0] : $default;
}

sub checkNetworkType {
    my $file = shift;
    my ($type, $isDomain) = ("UniProt", 0);

    if ($file =~ m/.zip$/) {
        $file = "unzip -c $file | sed '/<\\/node>/q' |";
    }

    my $success = open FILE, $file;
    if (not $success) {
        warn "Unable to scan input SSN $file for type: $!";
        return (0, 0);
    }

    while (<FILE>) {
        if (m/<node .*label="([^"]+)"/) {
            $isDomain = ($1 =~ m/:/);
        } elsif (m/<\/node/) {
            last;
        } elsif (m/<att .*UniRef(\d+) /) {
            $type = "UniRef$1";
        }
    }

    close FILE;

    return ($type, $isDomain);
}

sub computeRamReservation {
    my $fileSize = shift || 0;

    # Y = MX+B, M=emperically determined, B = safety factor; X = file size in MB; Y = RAM reservation in GB
    my $ramReservation = 150;
    if ($fileSize) {
        my $ramPredictionM = 0.03;
        my $ramSafety = 10;
        $fileSize = $fileSize / 1024 / 1024; # MB
        $ramReservation = $ramPredictionM * $fileSize + $ramSafety;
        $ramReservation = int($ramReservation + 0.5);
    }

    return $ramReservation;
}

1;

