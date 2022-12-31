BASE="/home/n-z/noberg/dev/EFITools"

PATH="$BASE/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="$BASE/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="$BASE/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"$BASE/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=$BASE/perl5"; export PERL_MM_OPT;

