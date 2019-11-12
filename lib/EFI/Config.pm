
package EFI::Config;

use strict;
use Exporter qw(import);
use FindBin;
use Config::IniFiles;
use Log::Message::Simple qw[:STD :CARP];


#our @EXPORT_OK = qw(build_config database_configure);


use constant {
    DATABASE_SECTION            => "database",
    DATABASE_USER               => "user",
    DATABASE_PASSWORD           => "password",
    DATABASE_NAME               => "database",
    DATABASE_HOST               => "host",
    DATABASE_PORT               => "port",
    DATABASE_IP_RANGE           => "ip_range",
    DATABASE_DBI                => "dbi",
    DATABASE_MYSQL              => "mysql",
    DATABASE_SQLITE3            => "sqlite3",

    IDMAPPING_SECTION           => "idmapping",
    IDMAPPING_TABLE_NAME        => "table_name",
    IDMAPPING_MAP_SECTION       => "idmapping.maps",
    IDMAPPING_REMOTE_URL        => "remote_url",
    IDMAPPING_UNIPROT_ID        => "uniprot_id",
    IDMAPPING_ENABLED           => "enabled",

    CLUSTER_SECTION             => "cluster",
    CLUSTER_QUEUE               => "queue",
    CLUSTER_EXTRA_PATH          => "extra_path",

    DBBUILD_SECTION             => "database-build",
    DBBUILD_UNIPROT_URL         => "uniprot_url",
    DBBUILD_INTERPRO_URL        => "interpro_url",
    DBBUILD_PFAM_INFO_URL       => "pfam_info_url",

    TAX_SECTION                 => "taxonomy",
    TAX_REMOTE_URL              => "remote_url",

    ENVIRONMENT_DB              => "EFI_DB",
    ENVIRONMENT_CONFIG          => "EFI_CONFIG",
    ENVIRONMENT_DBI             => "EFI_DBI",
};


our @EXPORT = qw(database_configure parseConfigFile ENVIRONMENT_DB ENVIRONMENT_CONFIG ENVIRONMENT_DBI DATABASE_SQLITE3);


use constant NO_ACCESSION_MATCHES_FILENAME => "no_accession_matches.txt";
use constant FASTA_ID_FILENAME => "userfasta.ids.txt";
use constant FASTA_META_FILENAME => "fasta.metadata";
use constant ANNOTATION_SPEC_FILENAME => "annotation.spec";



sub build_configure {
    my ($object, %args) = @_;

    croak "config_file_path argument is required" if not $args{config_file_path};

    #$configFilePath = $FindBin::Bin . "/../conf/build.conf";
    #if (exists $args{config_file_path}) {
    #    $configFilePath = $args{config_file_path};
    #} elsif (exists $ENV{EFI_BUILD_CONFIG}) {
    #    $configFilePath = $ENV{EFI_BUILD_CONFIG};
    #}
    #
    #if (exists $args{dryrun}) {
    #    $object->{dryrun} = $args{dryrun};
    #} else {
    #    $object->{dryrun} = 0;
    #}

    parseBuildConfig($object, $args{config_file_path});
}


# $configFile can be an already-parsed hash reference (parsed by parseConfigFile below; this would happen if
# another code has already parsed the file), or a path to a file.
# $conf is an optional parameter which can be used to put parameters in, if it is part of another object.
# Otherwise a hashref is returned.
sub database_configure {
    my $configFile = shift or die "Unable to configure database without configuration file";
    my $conf = shift;
    $conf = {} if not $conf;
    
    my $config;
    if (not ref $configFile) {
        $config = parseConfigFile($configFile);
    } else {
        $config = $configFile;
    }

    validateDatabaseConfig($config, $conf);

    return $conf;
}







#######################################################################################################################
# UTILITY METHODS
#


sub parseConfigFile {
    my $filePath = shift;

    my $section = "";
    my $data = {};

    open my $fh, $filePath or die "Unable to read config file $filePath: $!";
    while (<$fh>) {
        s/^\s*(.*?)\s*$/$1/s;
        s/;.+$//;
        next if not $_;
        if (m/^\[(.*)\]/) {
            $section = $1;
        } elsif (length) {
            my @parts = split(m/=/, $_, 2);
            if (scalar @parts == 1) {
                push @{$data->{$section}->{_raw}}, $parts[0];
            } else {
                my ($key, $val) = @parts;
                if (exists $data->{$section}->{$key}) {
                    $data->{$section}->{$key} = [$data->{$section}->{$key}] if not ref $data->{$section}->{$key};
                    push @{$data->{$section}->{$key}}, $val;
                } else {
                    $data->{$section}->{$key} = $val;
                }
            }
        }
    }

    return $data;
}


# Return 0 if it's OK, error message if it's not.
sub validateDatabaseConfig {
    my $config = shift;
    my $conf = shift;
    
    my $defaultHost = "localhost";
    my $defaultPort = 3306;
    my $defaultDbi = "mysql";

    $conf->{user} = $config->{database}->{user} // "";
    $conf->{password} = $config->{database}->{password} // "";
    $conf->{host} = $config->{database}->{host} // $defaultHost;
    $conf->{port} = $config->{database}->{port} // $defaultPort;
    $conf->{ip_range} = $config->{database}->{ip_range} // "";
    $conf->{dbi} = $config->{database}->{dbi} // $defaultDbi;
    $conf->{name} = $config->{database}->{name} // "";

    # Override the name from the environment if the environment provides a database name and DBI
    $conf->{name} = $ENV{&ENVIRONMENT_DB} if $ENV{&ENVIRONMENT_DB};
    $conf->{dbi} = $ENV{&ENVIRONMENT_DBI} if $ENV{&ENVIRONMENT_DBI};

    if ($conf->{dbi} eq DATABASE_MYSQL) {
        return getError(DATABASE_USER)               if not defined $conf->{user};
        return getError(DATABASE_PASSWORD)           if not defined $conf->{password};
    }
    return getError(DATABASE_NAME)                   if not defined $conf->{name};

    return 0;
}


sub parseBuildConfig {
    my ($object, $configFilePath) = @_;

    croak "The configuration file " . $configFilePath . " does not exist." if not -f $configFilePath;

    my $cfg = new Config::IniFiles(-file => $configFilePath);
    croak "Unable to parse config file: " . join("; ", @Config::IniFiles::errors), "\n" if not defined $cfg;

    $object->{id_mapping}->{table} = $cfg->val(IDMAPPING_SECTION, IDMAPPING_TABLE_NAME);
    $object->{id_mapping}->{remote_url} = $cfg->val(IDMAPPING_SECTION, IDMAPPING_REMOTE_URL);
    $object->{id_mapping}->{uniprot_id} = $cfg->val(IDMAPPING_SECTION, IDMAPPING_UNIPROT_ID);
        
    $object->{id_mapping}->{map} = {};
    if ($cfg->SectionExists(IDMAPPING_MAP_SECTION)) {
        my @idParms = $cfg->Parameters(IDMAPPING_MAP_SECTION);
        foreach my $p (@idParms) {
            $object->{id_mapping}->{map}->{lc $p} = 
                $cfg->val(IDMAPPING_MAP_SECTION, $p) eq IDMAPPING_ENABLED ?
                1 :
                0;
        }
    }

    croak getError(IDMAPPING_TABLE_NAME)            if not defined $object->{id_mapping}->{table};
    croak getError(IDMAPPING_REMOTE_URL)            if not defined $object->{id_mapping}->{remote_url};

    $object->{build}->{uniprot_url} = $cfg->val(DBBUILD_SECTION, DBBUILD_UNIPROT_URL);
    $object->{build}->{interpro_url} = $cfg->val(DBBUILD_SECTION, DBBUILD_INTERPRO_URL);
    $object->{build}->{pfam_info_url} = $cfg->val(DBBUILD_SECTION, DBBUILD_PFAM_INFO_URL);

    croak getError(DBBUILD_UNIPROT_URL)             if not defined $object->{build}->{uniprot_url};
    croak getError(DBBUILD_INTERPRO_URL)            if not defined $object->{build}->{interpro_url};
    croak getError(DBBUILD_PFAM_INFO_URL)           if not defined $object->{build}->{pfam_info_url};

    $object->{tax}->{remote_url} = $cfg->val(TAX_SECTION, TAX_REMOTE_URL);

    return 1;
}


sub getError {
    my ($key) = @_;

    return "The configuration file must provide the $key parameter.";
}


1;

