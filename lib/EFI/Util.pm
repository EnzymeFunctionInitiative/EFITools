
package EFI::Util;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(getLmod checkNetworkType);


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

1;

