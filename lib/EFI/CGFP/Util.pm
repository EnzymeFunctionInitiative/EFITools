
package EFI::CGFP::Util;


use Exporter;

@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(getAbundanceData expandMetanodeIds getClusterMap getMetagenomeInfo getClusterNumber expandMetanodeIdAttribute getClusterSizes);

#our ($IdentifyScript, $QuantifyScript, $ParseSSNScript);
#
#$IdentifyScript = "shortbred_identify.py";
#$QuantifyScript = "shortbred_quantify.py";
#$ParseSSNScript = "parse_ssn.py";





sub getClusterMap {
    my $file = shift;

    my $data = {};
    
    if (not defined $file or not -f $file) {
        return $data;
    }

    open FILE, $file;

    while (<FILE>) {
        chomp;
        my ($cluster, $protein) = split(m/\t/);
        $cluster = "N/A" if not defined $cluster or not length $cluster;
        $data->{$protein} = $cluster if defined $protein and $protein;
    }

    close FILE;

    return $data;
}



sub getAbundanceData {
    my $protFile = shift;
    my $clustFile = shift;
    my $cleanId = shift;
    my $isMerged = shift; # Load a merged results file as opposed to an individual quantify run file

    $cleanId = 1 if not defined $cleanId; # By default we remove the cluster number from the front of the protein name
    $isMerged = 0 if not defined $isMerged;

    my $abd = {metagenomes => [], proteins => {}, clusters => {}};

    if (defined $protFile and -f $protFile) {
        open PROT, $protFile or die "Unable to open protein file $protFile: $!";

        my $header = <PROT>;
        chomp($header);
        my @headerParts = split(m/\t/, $header);
        my ($hdrClusterNum, $protId, @mg);
        if ($isMerged) { 
            ($hdrClusterNum, $protId, @mg) = @headerParts;
        } else {
            ($protId, @mg) = @headerParts;
        }
        push(@{$abd->{metagenomes}}, @mg);

        while (<PROT>) {
            chomp;
            #my ($feature, @mgRes) = split(m/\t/);
            my (@parts) = split(m/\t/);
            my ($clusterNum, $feature, @mgRes);
            if ($isMerged) {
                ($clusterNum, $feature, @mgRes) = @parts;
            } else {
                ($feature, @mgRes) = @parts;
                my $tempId;
                ($clusterNum, $tempId) = split(m/\|/, $feature);
                $feature = $tempId if $cleanId and defined $tempId and $tempId =~ m/^[A-Z0-9]{6,10}$/;
            }
     
            #$feature =~ s/^([^\|]+)\|// if $cleanId;
            for (my $i = $#mgRes; $i < $#mg; $i++) { # Ensure that there are the same amount of results as metagenome headers
                push(@mgRes, 0);
            }
     
            #push(@{$abd->{proteins}->{$feature}}, @mgRes);
            for (my $i = 0; $i <= $#mg; $i++) {
                my $mgId = $mg[$i];
                $abd->{proteins}->{$feature}->{$mgId} = $mgRes[$i];
            }
        }

        close PROT;
    }

    if (defined $clustFile and -f $clustFile) {
        open CLUST, $clustFile or die "Unable to open cluster file $clustFile: $!";

        my $header = <CLUST>;
        chomp($header);
        my ($feat, @mg) = split(m/\t/, $header);
        push(@{$abd->{metagenomes}}, @mg) if not scalar @{$abd->{metagenomes}};

        while (<CLUST>) {
            chomp;
            my ($feature, @mgRes) = split(m/\t/);
            for (my $i = $#mgRes; $i < $#mg; $i++) { # Ensure that there are the same amount of results as metagenome headers
                push(@mgRes, 0);
            }
            #push(@{$abd->{clusters}->{$feature}}, @mgRes);
            for (my $i = 0; $i <= $#mg; $i++) {
                my $mgId = $mg[$i];
                $abd->{clusters}->{$feature}->{$mgId} = $mgRes[$i];
            }
        }

        close CLUST;
    }

    return $abd;
}


# Expand metanodes into their constituent parts (e.g. expand UniRef seed sequence clusters, as well as SSN repnode networks).
# Call this on an XML node that represents an SSN node.
sub expandMetanodeIds {
    my $nodeId = shift;
    my $xmlNode = shift;
    my $efiAnnoUtil = shift;

    my @nodes;

    my @annotations = $xmlNode->findnodes('./*');

    foreach my $annotation (@annotations) {
        my $attrName = $annotation->getAttribute('name');
        if ($efiAnnoUtil->is_expandable_attr($attrName)) {
            #print "Expanding $attrName\n";
            my @accessionlists = $annotation->findnodes('./*');
            foreach my $accessionlist (@accessionlists) {
                #make sure all accessions within the node are included in the gnn network
                my $attrAcc = $accessionlist->getAttribute('value');
                #print "         Expanded $nodeId into $attrAcc\n";
                push @nodes, $attrAcc if $nodeId ne $attrAcc;
            }
        }
    }

    return @nodes;
}


sub getClusterNumber {
    my $nodeId = shift;
    my $xmlNode = shift;

    # Due to a bug in GNT, multiple instances of the attributes may exist for the same node.  We
    # don't exit the loop below until iterated through all attributes because we want to pick
    # the last entry.
    my $val = "";

    my @annotations = $xmlNode->findnodes('./*');
    foreach my $annotation (@annotations) {
        my $attrName = $annotation->getAttribute('name');
        if ($attrName eq "Cluster Number") {
            $val = $annotation->getAttribute('value');
            last;
        } elsif ($attrName eq "Singleton Number") {
            $val = "S" . $annotation->getAttribute('value');
            last;
        }
    }

    return $val;
}


sub getMetagenomeInfo {
    my $dbList = shift;

    my $data = {};
    my $meta = {};

    my @dbs = split(m/,/, $dbList);
    foreach my $dbFile (@dbs) {
        (my $dbDir = $dbFile) =~ s%^(.*)/[^/]+$%$1%;
        open DB, $dbFile or next;
        while (<DB>) {
            next if m/^#/;
            chomp;
            my ($id, $name, $gender, $file) = split(m/\t/);
            
            if ($name =~ m/-/) {
                my ($name_id, $name_bodysite) = split(m/-/, $name);
                $name_bodysite =~ s/^\s*(.*?)\s*$/$1/g;
                $name = $name_bodysite;
            }

            if ($file !~ m%/%) {
                $file = "$dbDir/$id/$file";
            } elsif ($file !~ m%^/%) { # Has a slash but not absolute; relative path
                $file = "$dbDir/$file";
            }
            $data->{$id} = {bodysite => $name, gender => $gender, file_path => $file};
        }
        close DB;

        my $metaFile = "$dbFile.metadata";
        if (-f $metaFile) {
            open META, $metaFile;
            while (<META>) {
                next if m/^#/;
                chomp;
                my ($bodysite, $color, $order) = split(m/\t/);
                $meta->{$bodysite} = {color => $color, order => $order};
            }
            close META;
        }
    }

    return ($data, $meta);
}


sub getClusterSizes {
    my $file = shift;

    my $data = {};

    open FILE, $file or die "Unable to open cluster size file $file: $!";

    while (<FILE>) {
        chomp;
        my ($cluster, $id) = split(m/\t/);
        $data->{$cluster} = 0 if not exists $data->{$cluster};
        $data->{$cluster}++;
    }

    close FILE;

    return $data;
}


1;

