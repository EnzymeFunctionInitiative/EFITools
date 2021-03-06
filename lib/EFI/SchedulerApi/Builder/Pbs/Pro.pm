
package EFI::SchedulerApi::Builder::Pbs::Pro;

use strict;
use warnings;

use constant TYPE => "pbspro";
use constant SUBMIT_CMD => "qsub";

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../../";

use parent qw(EFI::SchedulerApi::Builder::Pbs);


sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);

    #$self->{output} = "-j oe";
    $self->{shell} = "-S /bin/bash";
    $self->{sched_prefix} = "#PBS";
    $self->{output_file_seq_num} = "";
    $self->{output_file_seq_num_array} = "";
    $self->{arrayid_var_name} = "PBS_ARRAY_INDEX";
    $self->{default_wall_time} = $args{default_wall_time} // "01:00:00";

    return $self;
}

sub addPath {
    my ($self, $path) = @_;
    $self->{extra_env} = $path;
}

sub jobName {
    my ($self, $name) = @_;
    $self->{name} = "-N \"$name\"";
}

sub mailEnd {
    my ($self, $clear) = @_;
    if (defined($clear)) {
        $self->{mail} = "";
    } else {
        $self->{mail} = "-m e";
    }
}

sub mailError {
    my ($self, $clear) = @_;
    if (defined($clear)) {
        $self->{mail} = "";
    } else {
        $self->{mail} = "-m ea";
    }
}

sub jobArray {
    my ($self, $array) = @_;

    if (length($array)) {
        $self->{array} = "-J $array";
    } else {
        $self->{array} = "";
    }
}

sub queue {
    my ($self, $queue) = @_;

    $self->{queue} = "-q $queue";
}

# We assume wall time is in hours, if a numeric value is specified.
sub resource {
    my ($self, $numNodes, $procPerNode, $ram, $wallTime) = @_;

    $wallTime = $self->{default_wall_time} if not $wallTime;
    if ($wallTime =~ m/^[\d\.]+$/) {
        my $h = int($wallTime);
        my $m = int($wallTime * 60) % 60;
        my $s = int($wallTime * 3600) % 3600 - $m * 60;
        $wallTime = sprintf("%02d:%02d:%02d", $h, $m, $s);
    }
    
    my $mem = defined $ram ? "mem=$ram" : "mem=4";
    $mem .= "gb" if $mem !~ m/gb$/i;

    $self->{res} = ["-l select=$numNodes:ncpus=$procPerNode:$mem,walltime=$wallTime"];
}

sub dependency {
    my ($self, $isArray, $jobId) = @_;

    if (defined $jobId) {
        my $okStr = $isArray ? "afterok" : "afterok";
        my $depStr = "";
        if (ref $jobId eq "ARRAY") {
            $depStr = join(",", map { s/\s//sg; "$okStr:$_" } @$jobId);
        } else {
            $depStr = "$okStr:$jobId";
        }
        $self->{deps} = "-W depend=$depStr";
    }
}

sub workingDirectory {
    my ($self, $workingDir) = @_;
    $self->{working_dir} = "-w $workingDir";
}

sub node {
    my ($self, $node) = @_;
}

1;

