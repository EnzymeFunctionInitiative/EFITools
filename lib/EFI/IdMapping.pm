
package EFI::IdMapping;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../";

use DBI;
use Log::Message::Simple qw[:STD :CARP];
use EFI::Config qw(database_configure);
use EFI::SchedulerApi;
use EFI::Database;
use EFI::IdMapping::Util;



sub new {
    my ($class, %args) = @_;

    my $self = {};
    bless($self, $class);

    $self->{db} = database_configure($args{config_file_path});

    # $self->{db} is defined by database_configure
    $self->{db_obj} = new EFI::Database(%args);

    $self->{dbh} = $self->{db_obj}->getHandle();

    $self->{has_table} = $self->checkForTable();
    # By default we check uniprot IDs for existence in idmapping table. This can be
    # turned off by providing argument uniprot_check = 0
    $self->{uniprot_check} = exists $args{uniprot_check} ? $args{uniprot_check} : 0;

    $self->{type_map} = {
        "GI" => 1,
        "EMBL-CDS" => 1,
        "RefSeq" => 1,
        "PDB" => 1,
    };

    return $self;
}


sub checkForTable {
    my ($self) = @_;

}


sub reverseLookup {
    my ($self, $typeHint, @ids) = @_;

    if ($typeHint eq EFI::IdMapping::Util::UNIPROT) {
        return (\@ids, \[]);
    }

    if ($typeHint ne EFI::IdMapping::Util::AUTO and not exists $self->{type_map}->{$typeHint}) { #grep {$m->{$_}->[1] eq $typeHint} get_map_keys_sorted($self)) {
        return (undef, undef);
    }

    my @uniprotIds;
    my @noMatch;
    my %uniprotRevMap;

    foreach my $id (@ids) {
        my $type = $typeHint;
        $id =~ s/^\s*([^\|]*\|)?([^\s\|]+).*$/$2/;
        $type = check_id_type($id) if $typeHint eq EFI::IdMapping::Util::AUTO;
        next if $type eq EFI::IdMapping::Util::UNKNOWN;

        my $foreignIdCol = "foreign_id";
        my $foreignIdCheck = " and foreign_id_type = '$type'";
        if ($type eq EFI::IdMapping::Util::UNIPROT) {
            if (not $self->{uniprot_check}) {
                (my $upId = $id) =~ s/\.\d+$//;
                push(@uniprotIds, $upId);
                push(@{ $uniprotRevMap{$upId} }, $id);
                next;
            }
            $foreignIdCol = "uniprot_id";
            $foreignIdCheck = "";
        }

        my $querySql = "select uniprot_id from idmapping where $foreignIdCol = '$id' $foreignIdCheck";
        my $row = $self->{dbh}->selectrow_arrayref($querySql);
        if (defined $row) {
            push(@uniprotIds, $row->[0]);
            push(@{ $uniprotRevMap{$row->[0]} }, $id);
        } else {
            push(@noMatch, $id);
        }
    }
    
    return (\@uniprotIds, \@noMatch, \%uniprotRevMap);
}


sub finish {
    my ($self) = @_;

    $self->{dbh}->disconnect();
}


1;

