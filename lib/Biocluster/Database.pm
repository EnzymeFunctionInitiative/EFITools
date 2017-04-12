
package Biocluster::Database;

use strict;
use DBI;
use Log::Message::Simple qw[:STD :CARP];
require 'Config.pm';
use Biocluster::Config qw(biocluster_configure);


sub new {
    my ($class, %args) = @_;

    my $self = {};
    bless($self, $class);

    biocluster_configure($self, %args);

    if (exists $args{load_infile}) {
        $self->{load_infile} = $args{load_infile};
    } else {
        $self->{load_infile} = 0;
    }

    return $self;
}


#sub createTable {
#    my ($self, $tableName) = @_;
#
#    my $dbh = $self->getHandle();
#    my $result = 1;
#    eval {
#        $dbh->do("CREATE TABLE $tableName");
#        1;
#    } or do {
#        error("Creating table $tableName failed: $@");
#        $result = 0;
#    };
#
#    $dbh->finish();
#
#    return $result;
#}


sub loadTabular {
    my ($self, $tableName, $tabularFile) = @_;

    my $dbh = $self->getHandle();
    my $result = 1;
    eval {
        $dbh->do("load data local infile '$tabularFile' into table $tableName");
        1;
    } or do {
        error("Loading data from file '$tabularFile' failed: $@", 1);
        $result = 0;
    };

    $dbh->disconnect();

    return $result;
}


sub stuff {

#grant select,execute,show view on `efi_20170412`.* to 'efignn'@'10.1.0.0/255.255.0.0';
}


sub tableExists {
    my ($self, $tableName) = @_;

    my $dbh = $self->getHandle();

    my $sth = $dbh->table_info('', '', '', 'TABLE');
    while (my (undef, undef, $name) = $sth->fetchrow_array()) {
        if ($tableName eq $name) {
            $dbh->disconnect();
            return 1;
        }
    }

    $dbh->disconnect();
    return 0;
}


sub dropTable {
    my ($self, $tableName) = @_;

    my $dbh = $self->getHandle();

    my $ok = $dbh->do("drop table $tableName");

    $dbh->disconnect();

    return $ok;
}


sub createTable {
    my ($self, $schema) = @_;

    my $dbh = $self->getHandle();

    my $sql = $schema->getCreateSql();

    my $ok = $dbh->do($sql);

    #my $ok = $dbh->do("create table $tableName ($columnDefs)");
    #if (not $ok) { $dbh->disconnect(); return $ok; }
    #foreach my $idx (@indexes) {
    #    $ok = $dbh->do("create index " . $idx->[0] . " on $tableName (" . $idx->[1] . ")");
    #    if (not $ok) { $dbh->disconnect(); return $ok; }
    #}

    $dbh->disconnect();

    return $ok;
}















#######################################################################################################################
# UTILITY METHODS
#


sub getHandle {
    my ($self) = @_;

    my $connStr =
        "DBI:mysql" .
        ":database=" . $self->{db_name} .
        ":host=" . $self->{db_host} .
        ":port=" . $self->{db_port};
    $connStr .= ";mysql_local_infile=1" if $self->{load_infile};

    my $dbh = DBI->connect($connStr, $self->{db_user}, $self->{db_password});

    return $dbh;
}


1;

