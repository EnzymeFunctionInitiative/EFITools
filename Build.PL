use strict;
use warnings;
use Module::Build;
     
use 5.010;
     
my $builder = Module::Build->new(
	module_name         => 'EFI',
	license             => 'perl',
	dist_author         => [
				'Nils Olberg <noberg@illinois.edu>',
				'Daniel Davidson <danield@igb.illinios.edu>',
				'David Slater <dslater@illinois.edu>'
				],
	dist_abstract       => 'Enzyme Function Initiative Tools',
	create_makefile_pl  => 1,
	#script_files        => ['bin/*.pl' ],
	create_readme       => 1,
	requires            => {
		'perl'			=> '5.10.1',
		'DBI'			=> '1.609',
		'DBD::mysql'		=> '4.013',
		'DBD::SQLite'		=> '1.27',
		'Capture::Tiny'		=> '0.48',
		'Exporter'		=> '5.68',
		'Log::Message::Simple'	=> '0.10',
		'Test::More'		=> '1.302167',
		'Getopt::Long'		=> '2.51',
		'List::Utils'		=> '1.52',
		'List::MoreUtils'	=> '0.428',
		'IO::File'		=> '1.39',
		'XML::Writer'		=> '0.606',
		'XML::LibXML'		=> '1.70',
		'XML::Parser'		=> '2.36',
		'XML::LibXML::Reader'	=> '2.0201',
		'Data::Dumper'		=> '2.161',
		'Statistics::R'		=> '0.34',
		'File::Slurp'		=> '9999.27',
		'JSON'			=> '2.15',
		'Time::HiRes'		=> '1.9760',
		'Storable'		=> '2.56',
		'Scaler::Util'		=> '1.52',
		'Array::Utils'		=> '0.5',
	
	},
	build_requires      => {
	},
	meta_merge         => {
        	resources => {
			'homepage'   => 'https://efi.igb.illinois.edu',
			'repository' => 'https://github.com/EnzymeFunctionInitiative/EFITools',
			'bugtracker' => 'https://github.com/EnzymeFunctionInitiative/EFITools/Issues'
        		}
	},

);
     
$builder->create_build_script();
