package Hosts;

use strict;
use warnings;
#use Logger;
use Net::OpenSSH;
#our @EXPORT_OK ;
use Net::DNS::Resolver;

BEGIN {
        use Exporter () ;
        our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS) ;

        $VERSION     = '0.0.1' ;

        @ISA         = qw(Exporter) ;
        @EXPORT      = () ;
        push (@EXPORT, 'svc') ;
#        push (@EXPORT, 'PrintLine') ;
#        push (@EXPORT, 'PrintHLine') ;
        @EXPORT_OK   = qw() ;
        %EXPORT_TAGS = () ;
}

END {}

sub svc {




}


return 1;
