
use strict;
use warnings;

package EFI::SchedulerApi::Builder;

sub new {
    my ($class, %args) = @_;

    my $self = bless({}, $class);
    $self->{output} = "";
    $self->{array} = "";
    $self->{shell} = "";
    $self->{queue} = "";
    $self->{res} = [];
    $self->{mail} = "";
    $self->{name} = "";
    $self->{deps} = "";
    $self->{sched_prefix} = "";
    $self->{actions} = [];
    $self->{working_dir} = "";
    $self->{output_dir_base} = "";
    $self->{output_file_stderr} = "";
    $self->{output_file_stdout} = "";
    $self->{output_file_seq_num} = "";
    $self->{output_file_seq_num_array} = "";
    $self->{arrayid_var_name} = "";
    $self->{other_config} = $args{extra_headers} ? [@{$args{extra_headers}}] : [];
    $self->{dry_run} = ($args{dryrun} or $args{dry_run}) ? 1 : 0;
    # Echo the first part of all acctions
    $self->{echo_actions} = exists $args{echo_actions} ? $args{echo_actions} : 0;
    $self->{abort_script_on_action_fail} = exists $args{abort_script_on_action_fail} ? $args{abort_script_on_action_fail} : 1;
    $self->{extra_path} = $args{extra_path} ? $args{extra_path} : ""; # use this to add an export PATH=... to the top of every script
    $self->{run_serial} = $args{run_serial} ? 1 : 0;

    return $self;
}

sub jobName {
    my ($self, $name) = @_;
}

sub mailEnd {
    my ($self, $clear) = @_;
}

sub mailError {
    my ($self, $clear) = @_;
}

sub jobArray {
    my ($self, $array) = @_;
}

sub queue {
    my ($self, $queue) = @_;
}

sub resource {
    my ($self, $numNodes, $procPerNode, $ram, $walltime) = @_;
}

sub dependency {
    my ($self, $isArray, $jobId) = @_;
}

sub workingDirectory {
    my ($self, $workingDir) = @_;
}

sub node {
    my ($self, $node) = @_;
}

sub extraHeaders {
    my ($self, $extra) = @_;
    if (ref($extra) eq "ARRAY") {
        push @{$self->{other_config}}, @$extra;
    } else {
        push @{$self->{other_config}}, $extra;
    }
}

sub setScriptAbortOnError {
    my ($self, $doAbort) = @_;

    $self->{abort_script_on_action_fail} = $doAbort;
}

sub outputBaseFilepath {
    my ($self, $filepath) = @_;
    if ($filepath) {
        $self->{output_file_stderr} = "-e $filepath";
        $self->{output_file_stdout} = "-o $filepath";
    } else {
        $self->{output_file_stderr} = $self->{output_file_stdout} = "";
    }
}

sub outputBaseDirpath {
    my ($self, $dirpath) = @_;

    if ($dirpath) {
        $self->{output_dir_base} = $dirpath;
    } else {
        $self->{output_dir_base} = "";
    }
}

sub addAction {
    my ($self, $actionLineRaw) = @_;

    my ($actionLine, $echoLine) = $self->formatAction($actionLineRaw);
    push(@{$self->{actions}}, $echoLine) if $echoLine;
    push(@{$self->{actions}}, $actionLine);
}

sub prependAction {
    my ($self, $actionLineRaw) = @_;

    my ($actionLine, $echoLine) = $self->formatAction($actionLineRaw);

    unshift(@{$self->{actions}}, $actionLine);
    unshift(@{$self->{actions}}, $echoLine) if $echoLine;
}

sub formatAction {
    my ($self, $actionLine) = @_;

    my $echoLine = "";
    $actionLine =~ s/{JOB_ARRAYID}/\${$self->{arrayid_var_name}}/g;
    if ($self->{echo_actions}) {
        (my $cmdType = $actionLine) =~ s/^(\S+).*$/$1/g;
        $cmdType =~ s/[^A-Za-z0-9_\-\/]//g;
        $echoLine = "echo 'RUNNING $cmdType'";
    }

    return ($actionLine, $echoLine);
}

sub render {
    my ($self, $fh) = @_;

    if (not $self->{run_serial}) {
        $self->renderSchedulerHeader($fh);
    }

    print $fh "export PATH=$self->{extra_path}:\$PATH\n" if $self->{extra_path};
    print $fh "set -e\n" if $self->{abort_script_on_action_fail};

    foreach my $action (@{$self->{actions}}) {
        print $fh "$action\n";
    }
}

sub renderSchedulerHeader {
    my ($self, $fh) = @_;

    print $fh ("#!/bin/bash\n");
    my $pfx = $self->{sched_prefix};
    print $fh ("$pfx " . $self->{array} . "\n") if length($self->{array});
    #print $fh ("$pfx " . $self->{output} . "\n") if length($self->{output});
    print $fh ("$pfx " . $self->{shell} . "\n") if length($self->{shell});
    print $fh ("$pfx " . $self->{queue} . "\n") if length($self->{queue});
    foreach my $res (@{ $self->{res} }) {
        print $fh ("$pfx " . $res . "\n") if length($res);
    }
    print $fh ("$pfx " . $self->{deps} . "\n") if length($self->{deps});
    print $fh ("$pfx " . $self->{mail} . "\n") if length($self->{mail});
    print $fh ("$pfx " . $self->{working_dir} . "\n") if length($self->{working_dir});
    print $fh ("$pfx " . $self->{name} . "\n") if length($self->{name});
    print $fh ("$pfx " . $self->{node} . "\n") if $self->{node};
    print $fh join("\n", @{$self->{other_config}}), "\n" if scalar(@{$self->{other_config}});
    
    if (length $self->{output_file_stdout}) {
        if (length $self->{array}) {
            print $fh ("$pfx " . $self->{output_file_stdout} . ".stdout." . $self->{output_file_seq_num_array} . "\n");
        } else {
            print $fh ("$pfx " . $self->{output_file_stdout} . ".stdout." . $self->{output_file_seq_num} . "\n");
        }
    }

    if (length $self->{output_file_stderr}) {
        if (length $self->{array}) {
            print $fh ("$pfx " . $self->{output_file_stderr} . ".stderr." . $self->{output_file_seq_num_array} . "\n");
        } else {
            print $fh ("$pfx " . $self->{output_file_stderr} . ".stderr." . $self->{output_file_seq_num} . "\n");
        }
    }
}

sub renderToFile {
    my ($self, $filePath, $comment) = @_;

    $comment = $comment ? "$comment\n" : "";

    if ($self->{output_dir_base} && not $self->{output_file_stdout}) {
        (my $fileName = $filePath) =~ s{^.*/([^/]+)$}{$1};
        $self->outputBaseFilepath($self->{output_dir_base} . "/" . $fileName);
    } elsif (not $self->{output_file_stdout}) {
        $self->outputBaseFilepath($filePath)
    }

    my $openMode = $self->{run_serial} ? ">>" : ">";
    if ($self->{run_serial} and not -f $filePath) {
        initSerialScript($filePath);
    }

    if ($self->{dry_run}) {
        print $comment;
        $self->render(\*STDOUT);
    } else {
        open my $fh, $openMode, $filePath or die "Unable to open job script file $filePath for writing: $!";
        print $fh $comment;
        $self->render($fh);
        close $fh;
    }
}


sub initSerialScript {
    my $file = shift;
    open my $fh, ">", $file or die "Unable to write to serial-script $file: $!";
    print $fh "#!/bin/bash\n";
    close $fh;

    chmod 0755, $file;
}


1;

