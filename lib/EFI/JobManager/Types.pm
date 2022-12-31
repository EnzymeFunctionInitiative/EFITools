
package EFI::JobManager::Types;



use constant TYPE_ACCESSION => "ACCESSION";
use constant TYPE_BLAST => "BLAST";
use constant TYPE_CLUSTER => "CLUSTER";
use constant TYPE_COLORSSN => "COLORSSN";
use constant TYPE_FAMILIES => "FAMILIES";
use constant TYPE_FASTA => "FASTA";
use constant TYPE_FASTA_ID => "FASTA_ID";
use constant TYPE_CONVRATIO => "CONVRATIO";
use constant TYPE_NBCONN => "NBCONN";
use constant TYPE_TAXONOMY => "TAXONOMY";
use constant TYPE_GNN => "gnn";
use constant TYPE_GND => "diagram";
use constant TYPE_GENERATE => "generate";
use constant TYPE_ANALYSIS => "analysis";

use constant JOB_FINISH => "FINISH";


use Exporter qw(import);

our @EXPORT = qw(TYPE_ACCESSION TYPE_BLAST TYPE_CLUSTER TYPE_COLORSSN TYPE_FAMILIES TYPE_FASTA TYPE_FASTA_ID TYPE_CONVRATIO TYPE_NBCONN TYPE_TAXONOMY TYPE_GNN TYPE_GND TYPE_GENERATE TYPE_ANALYSIS JOB_FINISH);

1;

