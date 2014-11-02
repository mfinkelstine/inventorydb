package Logger;

use strict;
use warnings;
use Term::ANSIColor;

BEGIN {
        use Exporter () ;
        our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS) ;

        $VERSION     = '1.0' ;

        @ISA         = qw(Exporter) ;
        @EXPORT      = () ;
        push (@EXPORT, 'PrintDot') ;
        push (@EXPORT, 'timestamp') ;
        push (@EXPORT, 'log_create') ;
        push (@EXPORT, 'log_it') ;
#        push (@EXPORT, 'warn') ;
#        push (@EXPORT, 'error') ;
#        push (@EXPORT, '') ;
#        push (@EXPORT, 'log_create') ;
        @EXPORT_OK   = qw() ;
        %EXPORT_TAGS = () ;
}

END {}
sub PrintDot{
    my $colums  = shift; # Number of rows
    my $char    = shift; # Character to print
    my $title   = shift; #
    my $comment = shift; # host name

    
    if (!defined $colums )  { $colums  = "80"; }
    if (!defined $char)     { $char     = "."; }
    if (!defined $title)    { $title    = ""; }
    if (!defined $comment)  { $comment  = ""; }
    
    my ($t,$c,$tc);
    print $title;
    if ( $char eq "" ) {

        $t = length($title);
        $c = ($colums/2);
        for (my $i = 0; $i <= $c ; $i++) {print " " }
        print "$comment\n";
    } else {

        $t = length($title);
        $c = length($comment);
        $tc = ($colums - $t - $c );
        for (my $i = 0; $i <= $tc ; $i++) {print "$char" }
        print "$comment\n";
    }
}

sub PrintLine ($$$) {
        my $mode = shift ;     # if 1 print LF else, dont print LF
        my $length = shift ;   # the length of the line
        my $string = shift ;   # the string to print ;
        print $string ;
        for (my $i = length($string) ; $i <= $length ; $i++) { print " " ; }
        print "\n" if ($mode) ;
}


sub log_create {
    my $f   = shift;
    if (!defined $f) {
        $f = "/var/www/std/stands.log";
    }

    #print "Creating Log File : $f \n\n";
    
    if ( -e $f ) {
        unlink $f;
        open (LOG, ">>",$f) or print . timestamp() . " Unable To create file $f!!";
        my $msg = "File was Already exist recreated $f";
        &L_NOTICE($msg,$f);    
    } else {
        &L_NOTICE("Log File not Exist Creationg new one",$f);
    }
}

sub timestamp {

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d%02d%02d %02d:%02d:%02d",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    my $nice_tt = "[" .$nice_timestamp."]";

    return $nice_tt;
}
sub log_it {
    my $f       = shift;
    my $msg     = shift;
    my $level   = shift;
    my ($ef,$sf,$format);
    if (!defined $level){ 
        $level = "1";
    }
    
    #print "FILE PATH : " . $f ." TITLE : ".$msg." LEVEL : " . $level ."\n";  

    if (($level eq "1") or ($level eq "INFO") or ($level eq "info") ) {
        #print timestamp() . " |  INFO| " .$msg. "\n";
        &L_INFO($msg,$f);
    } elsif (($level eq "2") or ($level eq "WARN") or ($level eq "warn") ) {
        print timestamp() . " |  WARN| ". $msg."\n";
        &L_WARN($msg,$f);
    } elsif  (($level eq "3") or ($level eq "DEBUG") or ($level eq "debug") ) {
        print  timestamp(). " | DEBUG| ".$msg."\n";
        &L_DEBUG($msg,$f);
    } elsif  (($level eq "4") or ($level eq "ERR") or ($level eq "err") ) {
        #printf timestamp . " | ERROR| " . $msg ."\n";
        $level = "[ ERROR]";
        #$level = "[\033[1;35m ERROR\033[0m]";
        &L_ERR($msg,$f,$level);
    
    } elsif  (($level eq "6") or ($level eq "NOTICE") or ($level eq "notice") ) {
        #printf timestamp . " |NOTICE| " . $msg ."\n";
        &L_NOTICE($msg,$f);
    }
}

sub L_ERR {
    my $msg     = shift;
    my $f       = shift;
    my $l       = shift;
    #print "ERROR FH : $f \n";
    open (LOG, ">>",$f) or print "ERORR : Unable to open Log File";
    print LOG timestamp ." ". $l ." ". $msg ."\n";
    #print LOG timestamp . " [ ERROR] " . $msg ."\n";
}
sub L_WARN {

    my $msg     = shift;
    my $f       = shift;

    open ( LOG, ">>",$f) or print "ERORR : Unable to open Log File";
    print LOG timestamp . " [  WARN] " . $msg ."\n";
}
sub L_INFO {
    my $msg     = shift;
    my $f       = shift;
    if ( !defined  $f ) {
        $f = "/var/www/std/stands.log";
        print timestamp . " [ ERROR] : Log File not Exist Creating new LOG File $f \n";
        log_create($f);
    }
    
    open ( LOG, ">>",$f) or print "ERROR : Unable to open Log File";
    print LOG timestamp() . " [  INFO] " . $msg . "\n";
}
sub L_DEBUG {
    my $msg        = shift;
    my $f          = shift;

    open ( LOG, ">>",$f) or print "ERORR : Unable to open Log File";
    print LOG timestamp() . " [ DEBUG] ". $msg ."\n";
    #print LOG "[DEBUG] " . timestamp . ":" . $messages ."\n";
}
sub L_FATAL { 
    my $messages    = @_;
    my $f           = shift;
    open ( LOG, ">",$f) or print "ERORR : Unable to open Log File";
    print LOG timestamp " [ FATAL] " . $messages ."\n";
    #print LOG "[FATAL] " . timestamp . ":" . $messages ."\n";
}
sub L_NOTICE {
    my $msg     =   shift;
    my $f       =   shift;

    open (LOG,">>",$f) or print timestamp. "Unable to open File $f\n";
    print LOG timestamp() . " [NOTICE] ".$msg."\n";

}
sub level { 
    my $messages    = @_;
    my $f           = shift;
    open ( LOG, ">",$f) or print "ERORR : Unable to open Log File";
    print LOG timestamp " | LEVEL | " . $messages ."\n";
    #print LOG "[LEVEL] " . timestamp . ":" . $messages ."\n";
}
sub patarn { 
    my $messages    = @_;
    my $f           = shift;
    open ( LOG, ">",$f) or print "ERORR : Unable to open Log File";
    print LOG "[INFO] " . timestamp . ":" . $messages ."\n";
}
return (1);


=head
LOG LEVELS

1 INFO (inform) 
2 WARN (WARNINGS)
3 DEBUG
4 ERROR (ERR)
5 ALERT
6 NOTICE
7 CRITICAL (CRIT,FATAL)
8 EMERG (EMERGENCY)
* L_ALERT
* L_CRIT
* L_ERR
* L_WARN
* L_NOTICE
* L_INFO
* L_DBG

log format ---

[2012/03/28 19:23:18] [ INFO]
[2012/03/28 19:23:25] [ERROR]
[2012/03/28 19:23:28] [ WARN]
=cut

