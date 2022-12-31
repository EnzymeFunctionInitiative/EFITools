#!/bin/env perl

use strict;
use warnings;


use Getopt::Long;
use FindBin;
use Cwd qw(abs_path);
#use File::Basename qw(dirname);
use Data::Dumper;
use File::Path qw(make_path);
use File::Copy;
use Capture::Tiny qw(capture);


use constant RUNNING => 1;
use constant FINISHED => 2;
use constant ERROR => 3;

use lib "$FindBin::Bin/../lib";

use EFI::JobManager;
use EFI::JobManager::Info;
use EFI::Database;


my ($dbConfigFile, $dbName, $configFile, $debug, $queue, $memQueue, $checkForFinishOnly, $lockFile);

my $results = GetOptions(
    "db-config=s"   => \$dbConfigFile,
    "db-name=s"     => \$dbName,
    "config=s"      => \$configFile,
    "debug:s"       => \$debug,
    "queue=s"       => \$queue,
    "mem-queue=s"   => \$memQueue,
    "check-only"    => \$checkForFinishOnly,
    "lock-file=s"   => \$lockFile,
);


die "Need --db-name argument" if not $dbName;
die "Need --config argument" if not $configFile or not -f $configFile;


my $toolDir = abs_path("$FindBin::Bin/../");

my $config = parseConfigFile($configFile);

if (not try_lock($configFile, \$lockFile)) {
    print "Script is already running, exiting...\n";
    exit(0);
}

$dbConfigFile = getDbConfigFile();
configureQueue($config);



# 1 == only check if the jobs have finished
# 2 == finish, then check if there are any new jobs and list them
# 3 == finish, show any new jobs, and create the directories and script files, without submitting anything
# anything else, run the full process
$debug = (not defined $debug or ($debug == D_FINISH and $debug == D_SHOW_NEW and $debug == D_CREATE_NEW)) ? 0 : $debug;

my $db = new EFI::Database(config_file_path => $dbConfigFile, db_name => $dbName);
my $dbh = $db->getHandle();

my $manager = new EFI::JobManager(dbh => $dbh, config => $config, debug => $debug);

$manager->checkForJobFinish();

unlock($lockFile) and exit(0) if $checkForFinishOnly;


$manager->processNewJobs();

unlock($lockFile);































sub configureQueue {
    my $config = shift;
    die "Need queue value in config file" if not $config->{queue};
    die "Need mem_queue value in config file" if not $config->{mem_queue};
}


sub parseConfigFile {
    my $file = shift;

    open my $fh, "<", $file or die "Unable to read config file $file: $!";

    my $config = {};
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s*(.*?)\s*$/$1/;
        next if $line =~ m/^;/;
        next if not $line;

        my ($key, $val) = split(m/=/, $line, 2);
        if ($key =~ m/^([^\.]+)\.env$/) {
            push @{$config->{$key}}, $val;
        } else {
            $config->{$key} = $val;
        }
    }

    close $fh;

    return $config;
}


sub getDbConfigFile {
    if (not $dbConfigFile or not -f $dbConfigFile) {
        $dbConfigFile = $ENV{EFI_CONFIG} if $ENV{EFI_CONFIG} and -f $ENV{EFI_CONFIG};
        $dbConfigFile = "$toolDir/conf/efi.conf" if (not $dbConfigFile or not -f $dbConfigFile);
        $dbConfigFile = "$ENV{HOME}/.efi/efi.conf" if (not $dbConfigFile or not -f $dbConfigFile);
    }

    if (not -f $dbConfigFile) {
        die "--config file parameter or EFI_CONFIG env var is required.\n";
    }

    return $dbConfigFile;
}


sub try_lock {
    # Don't do any locking; the process isn't 100% fool-proof
    return 1;

    my $configFile = shift;
    my $lockFile = shift; # reference, so we can update it if necessary

    if (not $$lockFile) {
        my ($configFileName, $configFilePath, $configFileExt) = fileparse($configFile);
        $$lockFile = "$configFilePath/.$configFileName.lock";
    }

    open my $fh, ">", $lockFile;
    close $fh;
}
sub unlock {
    return 1;
    my $lockFile = shift;
    unlink $lockFile or die "Unable to unlock $lockFile";
}


