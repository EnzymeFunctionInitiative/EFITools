# EFITools

This website contains a collection of webtools for creating and interacting with sequence similarity networks (SSNs) and genome neighborhood networks (GNNs). These tools originated in the Enzyme Function Initiative, a NIH-funded research project to develop a sequence / structure-based strategy for facilitating discovery of in vitro enzymatic and in vivo metabolic / physiological functions of unknown enzymes discovered in genome projects. 

* Documentation and installation guide is located at https://efi.igb.illinois.edu/docs


# Example

    #!/bin/bash
    export EFI_DB_DIR=/home/groups/efi/databases/20221201/blastdb
    export EFI_DIAMOND_DB_DIR=/home/groups/efi/databases/20221201/blastdb
    export EFI_DBI=mysql
    export EFI_DB=efi_202212
    #export EFI_DBI=sqlite3
    #export EFI_DB=/path/to/efi.sqlite

    $EFI_HOME/bin/efi.pl --run-job-config /path/to/job-config-file

