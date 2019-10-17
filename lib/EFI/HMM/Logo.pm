
package EFI::HMM::Logo;

use strict;
use warnings;


require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(init_logo make_logo);


sub init_logo {
    eval "use Bio::HMM::Logo";
    return not $@;
}


sub make_logo {
    my ($hmmFile, $jsonFile, $pngFile) = @_;

    return if not $hmmFile;

    # create the logo object and pass it the path to the hmm file.
    my $logo = Bio::HMM::Logo->new({ hmmfile => $hmmFile });
    
    if ($jsonFile) {
        # generate the json string that can be used by the javascript
        # code to create an interactive graphic
        my $logo_json = $logo->as_json("info_content_above");
        open my $json_fh, ">", $jsonFile or warn "Unable to write to json file $jsonFile: $!" and return;
        print $json_fh $logo_json;
        close $json_fh;
    }
    
    if ($pngFile) {
        # create a static version of the logo and dump it to disk.
        my $logo_png = $logo->as_png("info_content_above");
        open my $image, ">", $pngFile or warn "Unable to write to png file $pngFile: $!" and return;
        binmode $image;
        print $image $logo_png;
        close $image;
    }
}

1;

