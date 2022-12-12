#!/bin/env perl

use strict;
use warnings 'all';

die "$0 requires directory and action arguments" if scalar(@ARGV) < 2;

my $lockPath = $ARGV[0];

my $action = $ARGV[1];
die "$0 requires valid action (lock, unlock) [$action given]" if $action ne "lock" and $action ne "unlock";


my $timeout = 3600; # seconds
my $interval = 30; # seconds

if ($action eq "lock") {
    my $cur = 0;
    while (-f $lockPath) {
        sleep($interval);
        $cur += $interval;
        if ($cur > $timeout) {
            die "Unable to lock file within $timeout seconds";
        }
    }
    
    open LOCK, "> $lockPath" or die "Unable to write lock file $lockPath: $!";
    print LOCK scalar(localtime), "\n";
    close LOCK;

} elsif ($action eq "unlock") {
    if (not -f $lockPath) {
        die "Can't unlock a file that doesn't exist!";
    }

    unlink($lockPath) or die "Unable to lock $lockPath: $!";
}


