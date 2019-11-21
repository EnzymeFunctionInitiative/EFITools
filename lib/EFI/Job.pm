
package EFI::Job;

use strict;
use warnings;

use constant RUN => 1;
use constant DRY_RUN => 2;
use constant NO_SUBMIT => 4;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../";

use Data::Dumper;
use Getopt::Long qw(:config pass_through);
use FindBin;

use EFI::SchedulerApi;
use EFI::Util qw(getSchedulerType getLmod);
use EFI::Util::System;
use EFI::Config;
use EFI::Constants;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {};
    bless($self, $class);

    my $parms = {};
    my $result = GetOptions(
        $parms, # options are stored in this hash
        "job-id=i",
        "config=s",
        "np=i",
        "queue=s",
        "mem-queue|memqueue=s",
        "scheduler=s",
        "dry-run|dryrun",
        #"cluster-node=s",
        "remove-temp=i",
        "dir-name|tmp=s",
        "job-dir|out-dir=s",
        "no-submit", # create the script files but don't submit them
        "serial-script=s", # file to place the serial execute commands into (has a default value)
    );

    my $homeDir = abs_path(dirname(__FILE__) . "/../../");
    $self->{tool_path} = "$homeDir/sbin"; #TODO: change sbin to whatever it should be.

    my $configFile = $parms->{config} // "";
    if (not $configFile or not -f $configFile) {
        $configFile = $ENV{EFI_CONFIG} if $ENV{EFI_CONFIG} and -f $ENV{EFI_CONFIG};
        $configFile = "$homeDir/conf/efi.conf" if not -f $configFile;
        $configFile = "$ENV{HOME}/.efi/efi.conf" if not -f $configFile;
    }
    if (not -f $configFile) {
        die "--config file parameter is required.\n";
    }

    $self->{config_file} = $configFile;
    $self->{db} = {};
    $self->{cluster} = {};
    $self->{modules} = {};
    $self->{conf} = {};
    $self->{startup_errors} = [];

    $self->{cluster}->{dry_run} = $parms->{"dry-run"} ? 1 : 0;

    # Command line arguments override config file values
    my $config = EFI::Config::parseConfigFile($configFile);

    my $err = addModuleConfig($config, $self->{modules});
    die "Error validating module config: $err\n" if $err;
    $err = addClusterConfig($config, $self->{cluster});
    die "Error validating cluster config: $err\n" if $err;
    $err = addDatabaseConfig($config, $self->{db});
    die "Error validating database config: $err\n" if $err;

    $err = validateOptions($parms, $self, $self->{conf});
    die "Error validating options: $err\n" if $err;

    return $self;
}


sub addDatabaseConfig {
    my $config = shift;
    my $conf = shift;

    database_configure($config, $conf);

    $conf->{blast}->{blast_db_dir} = $ENV{EFI_DB_DIR} // $config->{database}->{blast_db_dir} // "";
    $conf->{blast}->{diamond_db_dir} = $ENV{EFI_DIAMOND_DB_DIR} // $config->{database}->{diamond_db_dir} // "";
    $conf->{blast}->{uniref90_db} = $config->{database}->{uniref90_db} // "";
    $conf->{blast}->{uniref50_db} = $config->{database}->{uniref50_db} // "";
    $conf->{blast}->{uniprot_db}  = $config->{database}->{uniprot_db} // "";

    return "No database name is specified in the configuration file or in the environment." if not $conf->{name}; 
    return "No blast_db_dir in config file  or EFI_DB_DIR in environment is specified." if not $conf->{blast}->{blast_db_dir};
    return "No uniprot_db in config file is specified." if not $conf->{blast}->{uniprot_db};
}


sub addClusterConfig {
    my $config = shift;
    my $conf = shift;

    my $numSysCpu = getSystemSpec()->{num_cpu} - 1;
    my $autoSched = getSchedulerType();
    my $defaultScratch = "/scratch";

    $conf->{np} = $config->{cluster}->{np} // $numSysCpu;
    $conf->{queue} = $config->{cluster}->{queue} // "";
    $conf->{mem_queue} = $config->{cluster}->{mem_queue} // $conf->{queue};
    $conf->{scheduler} = $config->{cluster}->{scheduler} // $autoSched;
    $conf->{run_serial} = ($config->{cluster}->{serial} and $config->{cluster}->{serial} eq "yes") ? 1 : 0;
    $conf->{scratch_dir} = $config->{cluster}->{scratch_dir} // $defaultScratch;

    return "No queue is provided in configuration file." if not $conf->{queue};
}


sub addModuleConfig {
    my $config = shift;
    my $conf = shift;

    foreach my $key (keys %{$config}) {
        if ($key =~ m/^environment\.(.+)$/) {
            $conf->{group}->{$1} = $config->{$key}->{_raw};
        }
    }
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;
    my $conf = shift;

    $conf->{job_id} = $parms->{"job-id"} // 0;
    $conf->{remove_temp} = $parms->{"remove-temp"} // 1;
    $conf->{dir_name} = $parms->{"dir-name"} // "output";
    $conf->{job_dir} = $parms->{"job-dir"} // "";
    $conf->{no_submit} = $parms->{"no-submit"} // 0;
    $conf->{dry_run} = $parms->{"dry-run"} // 0;
    $conf->{serial_script} = $parms->{"serial-script"} // "";

    $conf->{job_dir_arg_set} = 1;
    if (not $conf->{job_dir}) {
        $conf->{job_dir} = $ENV{PWD};
        if (not $self->getUseResults()) {
            $conf->{job_dir_arg_set} = 0;
            return "Results already exist in the current directory.  Please use the --job-dir flag to use this directory, or remove the results." if -d "$conf->{job_dir}/output";
        }
    }
    $conf->{job_dir} = abs_path($conf->{job_dir});

    return "";
}


# This should be overridden in each job type, but it should call this function by $self->SUPER::getJobInfo().
sub getJobInfo {
    my $self = shift;
    my $jobId = $self->getJobId();
    my @info;
    push @info, [job_id => $jobId] if $jobId;
    return \@info;
}
# This should be overridden in each job type.
sub getUsage {
    my $self = shift;
    return "";
}
# This should be overridden in each job type.
sub getJobType {
    my $self = shift;
    return "";
}
# This can be overridden to indicate that results in the current directory should be used.
sub getUseResults {
    my $self = shift;
    return 0;
}
# This can be overridden so specific job types can create extra directories as needed, but this function MUST be called by invoking $self->SUPER::getJobInfo().
sub createJobStructure {
    my $self = shift;
    my $dir = $self->{conf}->{job_dir};
    my $outputDir = "$dir/output";
    mkdir $outputDir;
    my $scriptDir = "$dir/scripts";
    mkdir $scriptDir;
    my $logDir = "$dir/log";
    mkdir $logDir;
    return ($scriptDir, $logDir, $outputDir);
}


sub getJobEnvAction {
    my $self = shift;
    #TODO: support loading from env file
    return "module load";
}


sub getModuleLoad {
    my $self = shift;
    my $module = shift;
    #TODO: implement this properly and look the module up
    return $self->getJobEnvAction() . " " . $module;
}


sub getEnvironment {
    my $self = shift;
    my $name = shift;

    if ($self->{modules}->{group}->{$name}) {
        return @{$self->{modules}->{group}->{$name}} 
    } else {
        return ();
    }
}


sub getToolPath {
    my $self = shift;
    return $self->{tool_path};
}


sub getJobDir {
    my $self = shift;
    return $self->{conf}->{job_dir};
}


sub getJobDirArgumentSet {
    my $self = shift;
    return $self->{conf}->{job_dir_arg_set};
}


sub setOutputDirName {
    my $self = shift;
    my $dirName = "";
    $self->{conf}->{dir_name} = $dirName;
}


sub getOutputDir {
    my $self = shift;
    my $dir = $self->{conf}->{job_dir};
    $dir .= "/" . $self->{conf}->{dir_name} if $self->{conf}->{dir_name};
    return $dir;
}


sub getLogDir {
    my $self = shift;
    my $dir = $self->{conf}->{job_dir} . "/log";
    return $dir;
}


sub getSerialScript {
    my $self = shift;
    return $self->{conf}->{serial_script};
}


sub getNp {
    my $self = shift;
    return $self->{cluster}->{np};
}


sub getDryRun {
    my $self = shift;
    return $self->{cluster}->{dry_run};
}


sub getJobId {
    my $self = shift;
    return $self->{conf}->{job_id};
}


sub getConfigFile {
    my $self = shift;
    return $self->{config_file};
}


sub requestRam {
    my $self = shift;
    my $ram = shift;
    #TODO: implement a check that prevents requesting more memory than is available
    return $ram;
}


sub requestHighMemQueue {
    my $self = shift;
    my $B = shift;
    my $queue = $self->{cluster}->{mem_queue};
    $B->queue($queue);
}


sub getScratchDir {
    my $self = shift;
    return $self->{cluster}->{scratch_dir};
}


sub setJobDir {
    my $self = shift;
    my $dir = shift;
    $self->{conf}->{job_dir} = $dir;
}


sub createScheduler {
    my $self = shift;

    return $self->{scheduler} if $self->{scheduler};

    my $logDir = $self->getLogDir();
    my %schedArgs = (
        type => $self->{cluster}->{scheduler},
        queue => $self->{cluster}->{queue},
        resource => [1, 1, "35gb"],
        dry_run => $self->{cluster}->{dry_run},
        run_serial => $self->{cluster}->{run_serial},
        output_base_dirpath => $logDir,
    );
    #$schedArgs{output_base_dirpath} = $logDir if $logDir;
    #TODO:
    #$schedArgs{node} = $clusterNode if $clusterNode;
    #$schedArgs{extra_path} = $config->{cluster}->{extra_path} if $config->{cluster}->{extra_path};
    my $S = new EFI::SchedulerApi(%schedArgs);

    $self->{scheduler} = $S;

    return $S;
}


sub getScheduler {
    my $self = shift;
    $self->createScheduler() if not $self->{scheduler};
    return $self->{scheduler};
}


sub getSubmitStatus {
    my $self = shift;
    return (DRY_RUN | NO_SUBMIT) if $self->{cluster}->{dry_run};
    return NO_SUBMIT if $self->{conf}->{no_submit};
    return RUN;
}


sub hasErrors {
    my $self = shift;
    return scalar @{$self->{startup_errors}};
}


sub getErrors {
    my $self = shift;
    return @{$self->{startup_errors}};
}


sub addDatabaseEnvVars {
    my $self = shift;
    my $B = shift;

    $B->addAction("export " . &ENVIRONMENT_DBI . "=" . $self->{db}->{dbi});
    $B->addAction("export " . &ENVIRONMENT_DB . "=" . $self->{db}->{name});
}


sub getBlastDbDir {
    my $self = shift;
    return $self->{db}->{blast}->{blast_db_dir};
}


sub addBlastEnvVars {
    my $self = shift;
    my $B = shift;
    my $type = shift;

    $type = "uniprot" if not $type or $type ne "uniref50" and $type ne "uniref90";
    my $varName = uc($type);

    my $dbDir = $self->getBlastDbDir();
    $B->addAction("export EFI_DB_DIR=$dbDir");
    my $name = $self->{db}->{blast}->{"${type}_db"} // "";
    #TODO: handle error if the db doesn't exist
    $B->addAction("export EFI_${varName}_DB=$name");
}



# Utility methods

sub checkSafeFileName {
    my $file = shift;
    return $file !~ m%[^/a-zA-Z0-9\-_\.+=]%;
}


1;

