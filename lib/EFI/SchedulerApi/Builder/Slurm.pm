
package EFI::SchedulerApi::Builder::Slurm;

use strict;
use warnings;

use constant TYPE => "slurm";
use constant SUBMIT_CMD => "sbatch";

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::SchedulerApi::Builder);


sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);

    $self->{sched_prefix} = "#SBATCH";
    $self->{output_file_seq_num} = "%j";
    $self->{output_file_seq_num_array} = "%A-%a";
    $self->{arrayid_var_name} = "SLURM_ARRAY_TASK_ID";

    $self->extraHeaders("#SBATCH --kill-on-invalid-dep=yes");

    return $self;
}

sub jobName {
    my ($self, $name) = @_;
    $self->{name} = "--job-name=\"$name\"";
}

sub mailEnd {
    my ($self, $clear) = @_;
    if (defined($clear)) {
        $self->{mail} = "";
    } else {
        $self->{mail} = "--mail-type=END";
    }
}

sub mailError {
    my ($self, $clear) = @_;
    if (defined($clear)) {
        $self->{mail} = "";
    } else {
        $self->{mail} = "--mail-type=FAIL";
    }
}

sub jobArray {
    my ($self, $array) = @_;

    if (length($array)) {
        $self->{array} = "--array=$array";
    } else {
        $self->{array} = "";
    }
}

sub queue {
    my ($self, $queue) = @_;

    $self->{queue} = "--partition=$queue";
}

sub resource {
    my ($self, $numNodes, $procPerNode, $ram) = @_;

    my $mem = defined $ram ? "--mem=$ram" : "";

    $self->{res} = ["--nodes=$numNodes", "--tasks-per-node=$procPerNode", $mem];
}

sub dependency {
    my ($self, $isArray, $jobId) = @_;

    if (defined $jobId) {
        my $okStr = "afterok";
        my $depStr = "";
        if (ref $jobId eq "ARRAY") {
            $depStr = join(",", map { s/\s//sg; "$okStr:$_" } grep defined($_), @$jobId);
        } else {
            $depStr = "$okStr:$jobId";
        }
        $self->{deps} = "--dependency=$depStr";
    }
}

sub workingDirectory {
    my ($self, $workingDir) = @_;
    $self->{working_dir} = "-D $workingDir";
}

sub node {
    my ($self, $node) = @_;
    $self->{node} = "-w $node";
}


1;

