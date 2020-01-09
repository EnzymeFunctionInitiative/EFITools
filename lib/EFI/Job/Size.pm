
package EFI::Job::Size;

use strict;
use warnings;

use Exporter qw(import);

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../";

our @EXPORT_OK = qw(family_count fasta_file_count id_file_count);

use constant DEFAULT_RAM => 3;

sub new {
    my ($class, %args) = @_;

    my $self = {mem => {DEFAULT => DEFAULT_RAM}, walltime => {DEFAULT => 1}};
    bless $self, $class;

    $self->{dbh} = $args{dbh} if $args{dbh};

    my $confHandler = sub {
        my $struct = shift;
        my $hash = shift;
        foreach my $key (keys %$hash) {
            if ($key =~ m/DEFAULT/) {
                $struct->{DEFAULT} = makeFunction($hash->{$key});
            } elsif ($key ne "ALL") {
                $struct->{$key} = makeFunction($hash->{$key});
            }
        }
        if ($hash->{ALL}) {
            foreach my $key (keys %$struct) {
                $struct->{$key} = makeFunction($hash->{ALL});
            }
        }
    };

    $confHandler->($self->{mem}, $args{memory_config}) if $args{memory_config};
    $confHandler->($self->{mem}, $args{extra_memory_config}) if $args{extra_memory_config};
    $confHandler->($self->{walltime}, $args{walltime_config}) if $args{walltime_config};
    $confHandler->($self->{walltime}, $args{extra_walltime_config}) if $args{extra_walltime_config};

    return $self;
}


sub makeFunction {
    my $val = shift;
    #TODO: support parsing of functional inputs (e.g. 0.03*$file_size+10).
    if ($val !~ m/^[\d\.]+$/) {
        #TODO: parse function properly instead of using eval
        return sub { return DEFAULT_RAM; }
    } else {
        # Copy for closure
        my $retval = $val;
        return sub { return $retval; };
    }
}


sub getMemorySize {
    my $self = shift;
    my $jobType = shift;
    my $seqCount = shift || 0;

    if ($self->{mem}->{$jobType}) {
        return $self->{mem}->{$jobType}($seqCount);
    } else {
        return $self->{mem}->{DEFAULT}($seqCount);
    }
}


sub familySize {
    my $self = shift;
    my $jobType = shift;
    my $useUniRef = shift;
    my @fams = @_;

    return DEFAULT_RAM if not $self->{$jobType};
    die "Requires DB handle dbh arg" if not $self->{dbh};

    if (not $self->{_cached_total}) {
        my ($totalUniProt, $totalUniRef50, $totalUniRef90, $data) = family_count($self->{dbh}, @fams);
        $self->{_cached_total} = $useUniRef == 90 ? $totalUniRef90 : ($useUniRef == 50 ? $totalUniRef50 : $totalUniProt);
    }
    return $self->getMemorySize($jobType, $self->{_cached_total});
}


sub family_count {
    my $dbh = shift;
    my @fams = @_;

    my ($totalUniProt, $totalUniRef50, $totalUniRef90) = (0, 0, 0);
    my $data = {};
    
    foreach my $fam (@fams) {
        my $sql = "SELECT num_members, num_uniref50_members, num_uniref90_members FROM family_info WHERE family = '$fam'";
        my $sth = $dbh->prepare($sql);
        die "No sth" if not $sth;
        $sth->execute;
    
        my $row = $sth->fetchrow_hashref;
        next if not $row;
    
        $totalUniProt += $row->{num_members};
        $totalUniRef50 += $row->{num_uniref50_members};
        $totalUniRef90 += $row->{num_uniref90_members};
    
        $data->{$fam} = {
            uniprot => $row->{num_members},
            uniref50 => $row->{num_uniref50_members},
            uniref90 => $row->{num_uniref90_members},
        };
    }

    return ($totalUniProt, $totalUniRef50, $totalUniRef90, $data);
}


sub fastaSize {
    my $self = shift;
    my $jobType = shift;
    my $file = shift;
    return DEFAULT_RAM if not $self->{$jobType};
    if (not $self->{_cached_total}) {
        $self->{_cached_total} = fasta_file_count($file);
    }
    return $self->getMemorySize($jobType, $self->{_cached_total});
}


sub fasta_file_count {
    my $file = shift;
    my $size = `grep \\> $file | wc -l`;
    chomp $size;
    return $size;
}


sub idSize {
    my $self = shift;
    my $jobType = shift;
    my $file = shift;
    return DEFAULT_RAM if not $self->{$jobType};
    if (not $self->{_cached_total}) {
        $self->{_cached_total} = id_file_count($file);
    }
    return $self->getMemorySize($jobType, $self->{_cached_total});
}


sub id_file_count {
    my $file = shift;
    my $size = `wc -l $file`;
    chomp $size;
    return $size;
}


1;

