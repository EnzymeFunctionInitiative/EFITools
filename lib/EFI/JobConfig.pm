
package EFI::JobConfig;

use strict;
use warnings;

use Exporter 'import';

our @EXPORT = qw(LoadJobConfig);


sub LoadJobConfig {
    my $file = shift;
    my $defaults = shift;

    my $config = {};
    if (defined $defaults and ref($defaults) eq "HASH") {
        foreach my $key (keys %$defaults) {
            $config->{$key} = $defaults->{$key};
        }
    }

    return $config if not $file or not -f $file;

    open FILE, $file or die "Unable to read job config file $file: $!";

    while (<FILE>) {
        chomp;
        my ($param, $value) = split(m/\t/);
        $config->{$param} = $value;
    }

    close FILE;

    return $config;
}


1;

