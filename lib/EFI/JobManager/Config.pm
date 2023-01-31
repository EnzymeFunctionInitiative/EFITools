
package EFI::JobManager::Config;

use strict;
use warnings;

use EFI::JobManager::Types;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {};
    parseConfigFile($args{file}, $self);
    bless $self, $class;

    return $self;
}


sub parseConfigFile {
    my $file = shift;
    my $config = shift;

    open my $fh, "<", $file or die "Unable to read config file $file: $!";

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


sub getMemQueue {
    my $self = shift;
    return $self->{mem_queue};
}


sub getQueue {
    my $self = shift;
    return $self->{queue};
}


sub getGlobal {
    my $self = shift;
    my $key = shift;
    return $self->{$key} // "";
}


sub getValue {
    my $self = shift;
    my $type = shift;
    my $key = shift;
    $key = "$type.$key";
    return $self->{$key} // "";
}


sub getBaseOutputDirPath {
    my $self = shift;
    my $type = shift;
    return $self->getValue($type, "output_dir");
}


sub getResultsDirName {
    my $self = shift;
    my $type = shift;
    return $self->getValue($type, "results_dir_name");
}


sub getUploadsDir {
    my $self = shift;
    my $type = shift;
    return $self->getValue($type, "uploads_dir");
}


sub getFileNameField {
    my $self = shift;
    my $type = shift;

    if ($type eq TYPE_GENERATE) {
        return "generate_fasta_file";
    } elsif ($type eq TYPE_GNN) {
        return "filename";
    } elsif ($type eq TYPE_CGFP_IDENTIFY) {
        return "identify_filename";
    } else {
        return "";
    }
}


sub getEnv {
    my $self = shift;
    my $type = shift;

    my @env;
    if (exists $self->{"$type.env"} and scalar @{ $self->{"$type.env"} }) {
        push @env, @{ $self->{"$type.env"} };
    }

    my $envStr = join("\n", @env) . "\n";
    return $envStr;
}


1;

