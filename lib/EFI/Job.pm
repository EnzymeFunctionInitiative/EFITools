
package EFI::Job;

use strict;
use warnings;

use constant RUN => 1;
use constant DRY_RUN => 2;
use constant NO_SUBMIT => 4;
use constant SET_CORES => 1;
use constant SET_QUEUE => 2;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../";

use Data::Dumper;
use Getopt::Long qw(:config pass_through);
use FindBin;

use EFI::SchedulerApi;
use EFI::Util qw(getLmod);
use EFI::Util::System;
use EFI::Config;
use EFI::Constants;
use EFI::Job::Size;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {};
    bless($self, $class);

    my $parms = {};
    my $result = GetOptions(
        $parms, # options are stored in this hash
        "job-id|j=s",
        "config=s",
        "dry-run|dryrun",
        "keep-temp",
        "dir-name|tmp=s",
        "job-dir|out-dir=s",
        "no-submit", # create the script files but don't submit them
        "memory=s",
        "walltime=s",
        "help",
        "serial-script=s", # file to place the serial execute commands into (has a default value)
    );

    my $homeDir = abs_path(dirname(__FILE__) . "/../../");
    $self->{tool_path} = "$homeDir/sbin"; #TODO: change sbin to whatever it should be.
    $self->{home_dir} = $homeDir;

    my $configFile = $parms->{config} // "";
    if (not $configFile or not -f $configFile) {
        $configFile = $ENV{EFI_CONFIG} if $ENV{EFI_CONFIG} and -f $ENV{EFI_CONFIG};
        $configFile = "$homeDir/conf/efi.conf" if not -f $configFile;
        $configFile = "$ENV{HOME}/.efi/efi.conf" if not -f $configFile;
    }
    if (not -f $configFile) {
        die "--config file parameter is required.\n";
    }
    $configFile = abs_path($configFile);

    $self->{config_file} = $configFile;
    $self->{db} = {};
    $self->{cluster} = {};
    $self->{modules} = {};
    $self->{conf} = {};
    $self->{startup_errors} = [];
    $self->{completed_name} = "0.COMPLETED"; # completed flag file name

    $self->{cluster}->{dry_run} = $parms->{"dry-run"} ? 1 : 0;

    # Command line arguments override config file values
    my $config = EFI::Config::parseConfigFile($configFile);

    my $err = addModuleConfig($config, $self->{modules});
    die "Error validating module config: $err\n" if $err;
    $err = addClusterConfig($config, $self->{cluster});
    die "Error validating cluster config: $err\n" if $err;
    $err = addResourceConfig($config, $self->{cluster}, $parms);
    die "Error validating job.* resource config: $err\n" if $err;
    $err = addDatabaseConfig($config, $self->{db});
    die "Error validating database config: $err\n" if $err;

    $err = validateOptions($parms, $self, $self->{conf});
    die "Error validating options: $err\n" if $err;

    $self->{raw_config} = $config;

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


sub addResourceConfig {
    my $config = shift;
    my $conf = shift;
    my $parms = shift;

    my $memEnv = $parms->{"memory"} // "";
    my $walltimeEnv = $parms->{"walltime"} // "";

    my %sizeArgs;
    $sizeArgs{memory_config} = $config->{"job.memory"} if $config->{"job.memory"};
    $sizeArgs{walltime_config} = $config->{"job.walltime"} if $config->{"job.walltime"};
    $sizeArgs{extra_memory_config} = $config->{"job.memory.$memEnv"} if $memEnv and $config->{"job.memory.$memEnv"};
    $sizeArgs{extra_walltime_config} = $config->{"job.walltime.$walltimeEnv"} if $walltimeEnv and $config->{"job.walltime.$walltimeEnv"};

    $conf->{resources} = new EFI::Job::Size(%sizeArgs);

    return "";
}


sub addClusterConfig {
    my $config = shift;
    my $conf = shift;

    my $numSysCpu = getSystemSpec()->{num_cpu};
    my $defaultScratch = "/scratch";

    $conf->{np} = $config->{cluster}->{np} // $numSysCpu;
    $conf->{node_np} = $config->{cluster}->{node_np} // $numSysCpu;
    $conf->{queue} = $config->{cluster}->{queue} // "";
    $conf->{mem_queue} = $config->{cluster}->{mem_queue} // $conf->{queue};
    $conf->{scheduler} = $config->{cluster}->{scheduler} // "";
    $conf->{scratch_dir} = $config->{cluster}->{scratch_dir} // $defaultScratch;
    $conf->{max_queue_ram} = $config->{cluster}->{max_queue_ram} // 0;
    $conf->{max_mem_queue_ram} = $config->{cluster}->{max_mem_queue_ram} // 0;

    # set-cores == divide the requested amount of RAM by the max_queue_ram and set the number of CPU to that number.
    # set-queue == if > max_queue_ram, use mem_queue
    my $resMethod = $config->{cluster}->{mem_res_method} // "set-queue";
    $resMethod = $resMethod eq "set-cores" ? SET_CORES : SET_QUEUE;
    $conf->{mem_res_method} = $resMethod;
    
    $conf->{scheduler} = EFI::SchedulerApi::validateSchedulerType($conf->{scheduler});
    $conf->{run_serial} = EFI::SchedulerApi::isSerialScheduler($conf->{scheduler}) ? 1 : 0;

    return "No queue is provided in configuration file." if not $conf->{queue} and not $conf->{run_serial};
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
    $conf->{remove_temp} = defined $parms->{"keep-temp"} ? 0 : 1;
    $conf->{dir_name} = $parms->{"dir-name"} // "output";
    $conf->{results_dir_name} = $parms->{"results-dir-name"} // "results";
    $conf->{job_dir} = $parms->{"job-dir"} // "";
    $conf->{no_submit} = $parms->{"no-submit"} // 0;
    $conf->{dry_run} = $parms->{"dry-run"} // 0;
    $conf->{serial_script} = $parms->{"serial-script"} // "";
    $conf->{wants_help} = $parms->{"help"} ? 1 : 0;

    $conf->{job_dir_arg_set} = 1;
    if (not $conf->{job_dir}) {
        $conf->{job_dir} = $ENV{PWD};
        if (not $self->getUseResults()) {
            $conf->{job_dir_arg_set} = 0;
        }
    }
    $conf->{job_dir} = abs_path($conf->{job_dir}) // "";

    if ($conf->{serial_script}) {
        $self->{cluster}->{run_serial} = 1;
        $self->{cluster}->{scheduler} = EFI::SchedulerApi::getSerialScheduler();
        unlink $conf->{serial_script} if -f $conf->{serial_script};
    }

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
# This can/should be overridden in each job type.  If no job type is specified, this usage is displayed.
sub getUsage {
    my $self = shift;
    return getGlobalUsageArgs() . "\n\n" . getGlobalUsage(admin => 1);
}
sub getGlobalUsageArgs {
    return "[--job-id # --job-dir <JOB_DIR> --memory <CONFIG> --walltime <CONFIG> --config <FILE>]";
}
sub getGlobalUsage {
    my $admin = shift || 0;
    my $help = <<HELP;
    --job-id            the job number to assign to the job; this is the prefix to each file;
                        if not specified no prefix will be assigned to the output files and
                        job scripts (the file name will mirror that of the input file).
    --job-dir           the directory to store all of the inputs/outputs to the job; it will
                        contain scripts/ (the location for scripts submitted ot the cluster), log/
                        (the output from cluster jobs), and output/ (the directory where results
                        will be stored).
    --memory            the memory profile to use, if specified in the config file.
    --walltime          the walltime profile to use, if specified in the config file.
    --config            path to config file; by default this looks for a 'efi.conf' file in the
                        conf/ directory of EFITools. This can be overridden by adding this
                        parameter.
HELP
    if ($admin) {
        $help .= <<HELP;
    --help              if no valid job types are specified, this help is displayed; if a job type
                        is provided, shows the specific options for the job type.

ADVANCED OPTIONS: (only for administrators for testing purposes)
    --dry-run           doesn't create any directories or job scripts; outputs to the terminal
                        what would be submitted to the cluster.
    --no-submit         only create the job scripts, do not submit them to the cluster.
    --dir-name          the output directory name to put results into (defaults to output/).
    --keep-temp         adding this flag will not remove intermediate files; useful for debugging;
                        defaults to true (remove all intermediate files)
    --serial-script     output all of the cluster jobs into a single file that can be run on a
                        single cluster node, or on a stand-alone system. If serial mode is
                        enabled and this is not provided, then output is written to a script
                        file in scripts/.  If serial mode is not enabled in the conf file and
                        this is provided, it behaves like serial mode for the run of this script.
HELP
    }
    return $help;
}
# Each sub class saves it's job type into a global TYPE key.
sub getJobType {
    my $self = shift;
    return $self->{TYPE} // "";
}
# This can be overridden to indicate that results in the current directory should be used.
sub getUseResults {
    my $self = shift;
    return 0;
}
# This must be overridden in each job type.
sub makeJobs {
    my $self = shift;
    return ();
}
# This can be overridden so specific job types can create extra directories as needed, but this function MUST be called by invoking $self->SUPER::getJobInfo().
sub createJobStructure {
    my $self = shift;
    my $dir = $self->getJobDir();
    my $outputDir = "$dir/output";
    mkdir $outputDir;
    my $scriptDir = "$dir/scripts";
    mkdir $scriptDir;
    my $logDir = "$dir/log";
    mkdir $logDir;
    my $resultsDir = "$dir/results";
    mkdir $resultsDir;
    return ($scriptDir, $logDir, $outputDir);
}


# This is the public interface.  It does post-processing after the job objects are created
# before returning them to be executed.
sub createJobs {
    my $self = shift;
    my @jobs = $self->makeJobs();
    if ($self->{cluster}->{run_serial}) {
        my $name = $self->getJobType() // "efi";
        map {
            my $str = "#" x 10 . uc(" $_->{name} ") . "#" x (88-length($_->{name}));
            $_->{job}->prependAction("echo \"$str\"");
            $_->{job}->prependAction("\n#\n" . $str . "\n#");
            $_->{name} = $name;
        } @jobs;
    }

    my $job = $self->getBuilder();
    $self->requestResourcesByName($job, 1, 1, "fix_perms");
    my $dir = $self->getJobDir();
    $job->addAction("find $dir -type d -exec chmod a+rx \\{\\} \\;");
    $job->addAction("find $dir -type f -exec chmod a+r \\{\\} \\;");

    push @jobs, {job => $job, deps => [map { $_->{job} } @jobs], name => "fix_perms"};

    return @jobs;
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
        return @{$self->{modules}->{group}->{$name}};
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
    my $dir = $self->getJobDir();
    $dir .= "/" . $self->{conf}->{dir_name} if $self->{conf}->{dir_name};
    return $dir;
}


sub getResultsDir {
    my $self = shift;
    my $dir = $self->getJobDir();
    $dir .= "/" . $self->{conf}->{results_dir_name} if $self->{conf}->{results_dir_name};
    return $dir;
}


sub getHasResults {
    my $self = shift;
    my $dir = $self->getJobDir();
    $dir .= "/" . $self->{conf}->{dir_name};
    return -d $dir;
}


sub getWantsHelp {
    my $self = shift;
    return $self->{conf}->{wants_help};
}


sub getLogDir {
    my $self = shift;
    my $dir = $self->getJobDir() . "/log";
    return $dir;
}


sub getSerialScript {
    my $self = shift;
    if ($self->{conf}->{serial_script}) {
        return $self->{conf}->{serial_script};
    } else {
        my $scriptDir = $self->getJobDir() . "/scripts";
        mkdir $scriptDir if not -d $scriptDir;
        return "$scriptDir/$self->{TYPE}.sh";
    }
}


sub getSerialMode {
    my $self = shift;
    return $self->{cluster}->{run_serial} ? 1 : 0;
}


sub getNp {
    my $self = shift;
    return $self->{cluster}->{np};
}


sub getNodeNp {
    my $self = shift;
    return $self->{cluster}->{node_np};
}


sub getDryRun {
    my $self = shift;
    return $self->{cluster}->{dry_run};
}


sub getRemoveTemp {
    my $self = shift;
    return $self->{conf}->{remove_temp};
}


sub getJobId {
    my $self = shift;
    return $self->{conf}->{job_id};
}


sub getConfigFile {
    my $self = shift;
    return $self->{config_file};
}


sub getConfigValue {
    my $self = shift;
    my $section = shift || "";
    my $key = shift || "";
    return $self->{raw_config}->{$section} // {} if not $key;
    return $self->{raw_config}->{$section}->{$key} // "";
}


sub getHomePath {
    my $self = shift;
    return $self->{home_dir};
}


#PRIVATE METHOD
#TODO: build a bit of logic in here, so that if a single core is requested but max memory, that we
#bounce this to the mem_queue.
sub requestResources {
    my $self = shift;
    my $B = shift; # SchedulerApi::Builder object
    my $numNode = shift;
    my $numCpu = shift;
    my $ram = shift;
    my $walltime = shift || 0;

    my $memQueue = $self->{cluster}->{mem_queue} . ($self->getScheduler->supportsMultiQueue() ? ",$self->{cluster}->{queue}" : "");
    if ($self->{cluster}->{mem_res_method} eq SET_QUEUE) {
        if ($self->{cluster}->{max_queue_ram} and $ram > $self->{cluster}->{max_queue_ram}) {
            $B->queue($memQueue);
        }
        if ($self->{cluster}->{max_mem_queue_ram} and $ram > $self->{cluster}->{max_mem_queue_ram}) {
            $ram = $self->{cluster}->{max_mem_queue_ram};
        }
    }
    if ($numCpu == 1 and $self->{cluster}->{mem_res_method} eq SET_CORES and
        $self->{cluster}->{max_queue_ram} and $ram > $self->{cluster}->{max_queue_ram})
    {
        $numCpu = int($ram / $self->{cluster}->{max_queue_ram} + 0.5);
    }
    if ($numCpu > $self->{cluster}->{node_np}) {
        $numNode = int($numCpu / $self->{cluster}->{node_np} + 0.5);
        $numCpu = int($numCpu / $numNode + 0.5); # Divide equally among systems
    }
    my @args = ($numNode, $numCpu, "${ram}gb");
    push @args, $walltime if $walltime;
    $B->resource(@args);
}


sub requestResourcesByName {
    my $self = shift;
    my $B = shift;
    my $numNode = shift;
    my $numCpu = shift;
    my $name = shift;

    my $ram = $self->getMemorySize($name);
    my $walltime = $self->getWalltime($name);

    return $self->requestResources($B, $numNode, $numCpu, $ram, $walltime);
}


sub getMemorySize {
    my $self = shift;
    my $type = shift;
    my $seqCount = shift || 0;
    return $self->{cluster}->{resources}->getMemorySize($type, $seqCount);
}


sub getWalltime {
    my $self = shift;
    my $type = shift;
    my $seqCount = shift || 0;
    return $self->{cluster}->{resources}->getWalltime($type, $seqCount);
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


sub getDbHome {
    my $self = shift;
    return ($self->{db}->{db_home} // "");
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
        output_base_dirpath => $logDir,
    );
    $schedArgs{extra_headers} = $self->{modules}->{group}->{headers} if $self->{modules}->{group}->{headers};
    my $S = new EFI::SchedulerApi(%schedArgs);

    $self->{scheduler} = $S;

    return $S;
}


sub getScheduler {
    my $self = shift;
    $self->createScheduler() if not $self->{scheduler};
    return $self->{scheduler};
}


sub getBuilder {
    my $self = shift;
    my $S = $self->getScheduler();
    return $S->getBuilder();
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


sub getDiamondDbDir {
    my $self = shift;
    return $self->{db}->{blast}->{diamond_db_dir};
}


sub getSequenceDbName {
    my $self = shift;
    my $type = shift;

    $type = "uniprot" if not $type or $type ne "uniref50" and $type ne "uniref90";
    my $name = $self->{db}->{blast}->{"${type}_db"} // "";

    die "BLAST database $type does not exist\n" if not $name;

    return $name;
}


sub getBlastDbPath {
    my $self = shift;
    my $type = shift || "uniprot";
    return $self->getBlastDbDir() . "/" . $self->getSequenceDbName($type);
}


sub getDiamondDbPath {
    my $self = shift;
    my $type = shift || "uniprot";
    return $self->getDiamondDbDir() . "/" . $self->getSequenceDbName($type) . ".dmnd";
}


sub addBlastEnvVars {
    my $self = shift;
    my $B = shift;
    my $type = shift;

    $type = "uniprot" if not $type or $type ne "uniref50" and $type ne "uniref90";
    my $varName = uc($type);

    my $dbDir = $self->getBlastDbDir();
    $B->addAction("export EFI_DB_DIR=$dbDir");
    my $name = $self->getSequenceDbName($type);

    $B->addAction("export EFI_${varName}_DB=$name");
}



# Utility methods

sub checkSafeFileName {
    my $file = shift;
    return $file !~ m%[^/a-zA-Z0-9\-_\.+=]%;
}


1;

