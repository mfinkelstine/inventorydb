#!/usr/bin/perl

use strict;
use warnings;
use Socket;
use Net::OpenSSH;
#use Expect;
use XML::Simple;
use IO::Socket;
use Data::Dumper;
use DBI;
use FindBin qw($Bin);
use Term::ReadKey;
use lib "$Bin/../lib";

my $proto   =   "22";
my $timeout =   "1";

my $pass;
my $id;
my (@esxi_nics,$mosv,$esxi_osver,$mpds,$mpd,@esxi_disks,$esxi_hostname,$esxi_cpus,$esxi_cpuc,$esxi_nics,$esxi_mem);


my $progname    =   "Hardware Inventory DB";
my $progver     =   "v0.0.8";
my $mhostname;  # Machine Host name
my $msoftver;   # Machine Software Version
my $mvendor;    # Machine Vendor          
my $mmodule;    # Machine Module          
my $mtype;      # Machine Type            
my $mserial;    # Machine Serial          
my $mncpus;     # Machine N CPU Sockets     
my $mncpuc;     # Machine N CPU Cores       
my @mnicsinfo;  # Machine NIC's Array
my $mnicmac;    # Machine MAC Address
my $mnics=0;      # Machine NIC's           
my $mmemsize;   # Machine Memory Size     
my @madisks;    # Machine Array disks
my $mpdisks;    # Machine Physical Disks  
my $mtdisksize; # Machine Total Disks Size      
my $mimmip;     # Machine IMM IP          
my $mipaddr;    # Machine IP Address
my $tmp     =   "/tmp/";
my $dbhost  = "svtglpi";
my $dbname  = "inventory";
#my $dbname  = "inventorydb";
my $dbuser  = "root";
my $dbpass  = "a1b2c3";
my @sig_ip  =   ("9.151.184.", "9.151.185.");
my $iLOG     = "/tmp/hardware.log";
my $dbh;
my $hires_time = sub { time(); };
#print Dumper(\%machine_hw_info);
#printf " %4d $machine_hw_info{$_}" for (keys %machine_hw_info);
if (eval 'use Time::HiRes; 1') {
    $hires_time = \&Time::HiRes::time;
}
my $g_stime = $hires_time->();


##### START LOGS #######################################################################################
sub print_hst {
    my $line = join '', @_;
    chomp $line;
    my $stamp = sprintf "[ %.6f ] ", ($hires_time->() - $g_stime);
    #print $stamp, $line, "\n";
    #print LOG $stamp, $line;
    print HST $stamp, $line, "\n";
}
sub print_log {
    my $line = join '', @_;
    chomp $line;
    my $stamp = sprintf "[ %.6f ] ", ($hires_time->() - $g_stime);
    #print $stamp, $line, "\n";
    #print LOG $stamp, $line;
    print LOG $stamp, $line, "\n";
}
sub print_err {
    my $line = join '', @_;
    chomp $line;
    my $stamp = sprintf "[ %.6f ] ", ($hires_time->() - $g_stime);
    print ERR $stamp, $line, "\n";
}
sub print_error {
    print_err "ERROR: ", @_;
    #print "ERROR: ", @_, "\n";
}
sub print_info {
    print_log "INFO: ", @_, "\n";
    #print "INFO   : " , @_ ,"\n";
}
sub print_note {
    print_log "NOTE   : ", @_, "\n";
}
sub abort {
    print_error @_;
    die;
}
sub print_debug { 
    print_log "DEBUG: ", @_, "\n";
    print "DEBUG: ", @_ , "\n";
}
sub open_log {   
    unlink $iLOG;
    open LOG, ">", $iLOG;
    open ERR, ">", $iLOG.".err";
    open HST, ">", $iLOG.".hostlist";
    print_log "$progname $progver\n";
    print_log "Perl: ", $^X, " ", sprintf("v%vd", $^V), " ", $^O."\n";
    print_log "CYGWIN='", $ENV{CYGWIN}, "'\n";
}
##### END OF LOGS ######################################################################################

sub db_connect {
    ($dbname, $dbuser, $dbpass) = @_;
    $dbh = DBI->connect("DBI:mysql:$dbname;host=$dbhost",$dbuser,$dbpass) or die "Couldn't connect to database: " . DBI->errstr;;
    $dbh->do(qq{set character set 'utf8';});
    return $dbh;
    
}
sub do_sql {
# Takes: $dbh, $sql
#$dsn    Database source name
#$dbh    Database handle object
#$sth    Statement handle object
#$h      Any of the handle types above ($dbh, $sth, or $drh)
#$rc     General Return Code  (boolean: true=ok, false=error)
#$rv     General Return Value (typically an integer)
#@ary    List of values returned from the database.
#$rows   Number of rows processed (if available, else -1)
#$fh     A filehandle
#undef   NULL values are represented by undefined values in Perl
#\%attr  Reference to a hash of attribute values passed to methods
# # Returns: status
    my $dbh = shift || die "Database not connected!\n";
    my $sql = shift || die "Missing SQL statement???\n";
    print_note "SQL Statment - $sql";
    $dbh->do($sql) or die $dbh->errstr;
    if ($dbh->errstr) {
        return $dbh->do($sql);
    } else {return "ok";}
}
sub do_insert {
    my $dsn = shift || print "Database not connected!\n";
    my $table = shift || print "Missing table!\n";
    my $data = shift || print "Nothing to insert!\n";
    if (!defined($dbh) && !defined($table) && !defined($data)) {
        print_error "No Value to insert to databases";
        return;
    }
    my $insert = "INSERT INTO \`$table\` (`" . join('`,`', keys %$data) . '`) VALUES (\'' . join('\',\'', values %$data ) . '\');';
    print_note "Checking if data exist on Database : SQL VALUES " . $insert . "\n";
    my $retlevel = sql_query_check($dsn,$table,$data);
    if ($retlevel eq "0") {
        print_note "No data exist on DB : $$data{\"hostname\"} ";
    #print_note "No data exist on DB : $$data{\"inv_mos_name\"} ";
        do_sql($dsn,$insert);
    }else{
        print_note "MySql : $$data{\"hostname\"} exist on DB";
    #print_note "MySql : $$data{\"inv_mos_name\"} exist on DB";
    }
}
sub sql_query_check {

    my $dbh = shift || die print_error "Databases Not Connected !!! ";
    my $table = shift || die print_error "Table Not defined !!! ";
    my $data = shift || die print_error "No data have been defined!!! ";

### Checking if Database connected #####################################################################
    print_log "Checking Database conectivity";
    if ( not $dbh->ping) {
        print_error "Database not Connected : Rconnecting to $dbname";
        db_connect($dbname,$dbuser,$dbpass);
    }   

    if (!exists $data->{hostname} && !exists $data->{serial} ) {
        #if (!exists $data->{inv_mos_name} && !exists $data->{inv_mos_serial} ) {
        print_error "No Host and no Serial where defined";
        return;
    } else { 

### Checking if there are any record of specific host and serial #######################################
        my  $q = "SELECT hostname,serial FROM $table WHERE hostname='$$data{\"hostname\"}' AND serial='$$data{\"serial\"}';";
        #my  $q = "SELECT inv_mos_name,inv_mos_serial FROM $table WHERE inv_mos_name='$$data{\"inv_mos_name\"}' AND inv_mos_serial='$$data{\"inv_mos_serial\"}';";
        print_note "DB - Query : $q";
        my  $sth = $dbh->prepare($q);
            $sth->execute() or die print_error "$dbh->errstr"; 
        my $nrows = $sth->rows;
        #print_info "ex status from DB : $nrows";
        if ($nrows eq "1") {
            print_note "MySql : Data already exist on DB : hostname : ". $$data{"hostname"} ;
            #print_note "MySql : Data already exist on DB : hostname : ". $$data{"inv_mos_name"} ;
            return $nrows;
        } else {
            print_note"MySql : NO Data Found on DB : hostname : ".$$data{"hostname"};
            #print_note"MySql : NO Data Found on DB : hostname : ".$$data{"inv_mos_name"};
            return $nrows;
        }
    }
}

##### END OF LOGS ######################################################################################
sub print_results(){
    if (!defined($mhostname))  { $mhostname = "null"; print_error "Hostname : " .$mhostname; }else{ print_note "Hostname : " .($mhostname = leading_trailing($mhostname));} 
    if (!defined($mipaddr))    { $mipaddr   = "null"; print_error "Machine OS IP  : " .$mipaddr;} else{ print_note "Machine OS IP  : " .($mipaddr=leading_trailing($mipaddr))} 
    if (!defined($msoftver))   { $msoftver  = "N/A"; print_error "Machine OS Version : " .$msoftver; }else{ print_note "Machine OS Version : " .($msoftver = leading_trailing($msoftver));} 
    if (!defined($mvendor))    { $mvendor   = "N/A"; print_error "Machine Vendor : " .$mvendor; }else{ print_note "Machine Vendor : " .($mvendor = leading_trailing($mvendor));} 
    if (!defined($mmodule))    { $mmodule   = "N/A"; print_error "Machine Module : " .$mmodule;} else{ print_note "Machine Module : " .$mmodule;} 
    if (!defined($mtype))      { $mtype     = "N/A"; print_error  "Machine Type : " .$mtype; }else{ print_note "Machine Type : " .($mtype=leading_trailing( $mtype));} 
    if (!defined($mserial))    { $mserial   = "null"; print_error "Machine Serial : " .$mserial;}else{ print_note "Machine Serial : " .( $mserial = leading_trailing($mserial)) ;} 
    if (!defined($mncpus))     { $mncpus    = "N/A"; print_error "Machine Number of CPU's : " .$mncpus; }else{ print_note "Machine Number of CPU's : " . ($mncpus = leading_trailing($mncpus));} 
    if (!defined($mncpuc))     { $mncpuc    = "N/A"; print_error "Machine Number of Core's: " .$mncpuc; }else{ print_note "Machine Number of Core's: " .($mncpuc = leading_trailing($mncpuc));} 
    if (!defined($mnicmac))    { $mnicmac   = "null"; print_error "Machine Network MAC : " .$mnicmac; }else{ print_note "Machine Network MAC: " .($mnicmac = leading_trailing($mnicmac));} 
    if (!defined($mnics))      { $mnics     = "N/A"; print_error "Machine Number of NiC's: " .$mnics; }else{ print_note "Machine Number of NiC's: " .($mnics = leading_trailing($mnics));} 
    if (!defined($mmemsize))   { $mmemsize  = "N/A"; print_error "Machine Memory Size: " .$mmemsize; }else{ print_note "Machine Memory Size: " .($mmemsize = leading_trailing($mmemsize));} 
    if (!defined($mpdisks))    { $mpdisks   = "N/A"; print_error "Machine Pysical Disk : " .$mpdisks; }else{ print_note "Machine Pysical Disk : " .($mpdisks = leading_trailing($mpdisks));} 
    if (!defined($mtdisksize)) { $mtdisksize= "N/A"; print_error "Machine Disk Size : " .$mtdisksize; }else{ print_note "Machine Disk Size : " .($mtdisksize = leading_trailing($mtdisksize));} 
    chomp($mhostname,$mipaddr,$msoftver,$mvendor,$mmodule,$mtype, $mserial,$mncpus,$mncpuc,$mnics,$mnicmac,$mmemsize,$mpdisks,$mtdisksize);
     my   %hwinfo = ( 
        "hostname"      =>  "$mhostname",
        "ip"            =>  "$mipaddr",
        "serial"        =>  "$mserial",
        "mac"           =>  "$mnicmac");
        #"inv_mos_name"      =>  "$mhostname",
        #"inv_mos_ipaddr"    =>  "$mipaddr",
        #    "inv_mos_soft_ver"  =>  "$msoftver",
        #   "inv_mos_vendor"    =>  "$mvendor",
        #   "inv_mos_module"    =>  "$mmodule",
        #   "inv_mos_type"      =>  "$mtype",
        #"inv_mos_serial"    =>  "$mserial",
        #   "inv_mos_ncpu"      =>  "$mncpus",
        #   "inv_mos_ncpuc"     =>  "$mncpuc",
        #   "inv_mos_mnics"     =>  "$mnics",
        #"inv_mos_mnic"     =>  "$mnics");
        #   "inv_mos_memory"    =>  "$mmemsize",
        #   "inv_mos_mpd"       =>  "$mpdisks",
        #   "inv_mos_disksize"  =>  "$mtdisksize");

       do_insert($dbh,"Script_data",\%hwinfo);
}
sub leading_trailing {
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}
##### END OF LOGS ######################################################################################
sub esxi_info_v5($$$){
    my  $user   = shift;
    my  $pass   = shift;
    my  $ip     = shift;
    my  $mtnics  = "1"; #machine total nics
    #my @esxi_nics;
    
    my  $socket =   new IO::Socket::INET->new(PeerAddr => $ip, PeerPort => '22', Proto => 'tcp' , timeout => 1);
    if ($socket){
        my  $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>5 );
            if ($ssh->error){ 
                print "Unable to connect to remote host : " . $ip . " : ". $ssh->error;
                last;
            }
        my  @esxi_info =  $ssh->capture("esxcli hardware platform get");
            $esxi_osver = $ssh->capture("vmware -v");
            @esxi_disks=  $ssh->capture("esxcfg-scsidevs -c \| grep -i Local \| grep -v \"CD-ROM\"");
        $esxi_hostname = $ssh->capture("hostname");
        $esxi_mem =  $ssh->capture("esxcli hardware memory get \| grep \"Physical Memory:\" \| awk \'{print \$3}\'"); # Need to be devide by 1024/1024
        $esxi_mem = int($esxi_mem /1024/1024);
        $esxi_cpuc =  $ssh->capture("esxcli hardware cpu list \| grep CPU: \|  wc -l");
        $esxi_cpus =  $ssh->capture("esxcli hardware cpu list \| grep \"Package Id\" \| uniq \| wc -l");
        $esxi_nics =  $ssh->capture("esxcli network nic list \| egrep -v \"Name\|---\|vusb\"\|wc -l");
        
        foreach my $disk (@esxi_disks){
            ($mpd)  = $disk =~ m/^(naa.*?)\s/;
            ($mpds) = $disk  =~ m/\s(\d+.*MB)\s/;  
        } 
        $mtnics     =   scalar(@esxi_nics);
        print "Machine Information \n";
            foreach my $esxi (@esxi_info){
                chomp($esxi);
                if ($esxi =~ m/\s(Vendor Name:)/) {
                    $mvendor = $esxi;
                    $mvendor =~ s/\s+.*?:\s+//g;
                }elsif ($esxi =~ m/\s(Product Name:)/) {
                    $mtype = $esxi;
                    ($mtype) = $mtype =~ m/(\[.*\])/;
                    $mtype   =~ s/[\[\]]//g;
                    $mmodule = $esxi;
                    ($mmodule) = $mmodule =~ m/(S.*?\s-)/;
                    $mmodule =~ s/Server\s-//g;
                }
                elsif($esxi =~ m/\s(Serial Number:)/){
                    $mserial = $esxi;
                    $mserial =~ s/\s+.*?:\s+//g;
                }
            }
    #chomp($esxi_hostname,$mvendor,$mtype,$mserial,$mmodule,$esxi_cpus,$esxi_cpuc,$esxi_nics,$esxi_mem,$esxi_osver);
    print_results(); 
    }else{
        print "Port is Close on " . $ip ;
    }
    print "\n";
}

##################### HW Info
sub aix_info($$$){

    my $user    =   shift;
    my $pass    =   shift;
    my $ip      =   shift;

    
    #print "Checking AIX Machine.\n";
    my  $socket =   new IO::Socket::INET->new(PeerAddr => $ip, PeerPort => '22', Proto => 'tcp' , timeout => 1);

    if ($socket){
        my  $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>1 );
            if ($ssh->error){ 
                print_error "Unable to connect to remote host :" .$ip . " : ". $ssh->error;
                last;
            }

    $mhostname = $ssh->capture("hostname -s");
    chomp($mhostname);
    my $hwinfo  = "$tmp$mhostname.hwinfo.log";
    
    $ssh->capture2("/usr/sbin/prtconf > $hwinfo"); #### not working
    $ssh->scp_get({glob => 1}, '/tmp/*hwinfo.log', '/tmp');
    $mnicmac = `arp -a $ip | awk '{print \$4}'`;
    $mipaddr = $ip;
    open (MINFO, "$hwinfo") or return "Unable to open File $hwinfo";
    my @hwdata = <MINFO>;
    my @t = grep(s/\s*$//g, @hwdata);
        foreach my $line (@hwdata){
            chomp($line);
            if ($line =~ m/Machine Serial Number/){
                $mserial = (split(':',$line))[-1];
                $mserial =~ s/^\s+//;
                chomp($mserial);
            }
            elsif ($line =~ m/System Model/){
                my $type = (split(':',$line))[-1];
                ($mvendor,$mtype) = (split(',',$type))[0,1];
                $mvendor =~ s/^\s+//;
            }
            elsif ($line =~ m/Memory Size/) {
                $mmemsize = (split(':',$line))[-1];
                $mmemsize =~ s/^\s+//;
            }
            elsif ($line =~ m/(hdisk.?)\s+.*?SAS/){
                ($mpdisks)      = $line =~ m/\+\s(\w+)/;
                ($mtdisksize)   = $line =~ m/(\d+\s\w+)/;
            }
            elsif ($line =~ m/\+\s(ent.)/){
                $mnics += 1;
            }
            elsif($line =~ m/Number Of Processors:/){
                $mncpuc = (split(':',$line))[-1];
                $mncpuc =~ s/^\s//;
            }
        }
    close(MINFO);
        print_results();
    } else {
        print "Port is Close on ". $ip;
    }
}
sub esxi_info($$$) {
    
    my $user    =   shift;
    my $pass    =   shift;
    my $ip      =   shift;
    
    print_note "Checking VM Mahine Version.\n";
    my  $socket =   new IO::Socket::INET->new(PeerAddr => $ip, PeerPort => '22', Proto => 'tcp' , timeout => 1);

    if ($socket){
        my  $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>5 );
            if ($ssh->error){ 
                print_error "Unable to connect to remote host :".$ip. " : " . $ssh->error;
                last;
            }
        $mhostname = $ssh->capture("hostname -s");
        chomp($mhostname); 
        $msoftver = $ssh->capture("vmware -v");
        chomp($msoftver);
        @mnicsinfo  =  $ssh->capture("esxcfg-nics -l \| egrep -v \"Name\|vusb\"");
        $mnics  = scalar(@mnicsinfo);
    my $hwinfo  = "$tmp$mhostname.hwinfo.log";
    
    @madisks = $ssh->capture("fdisk -l 2> /dev/null \| grep \"^Disk\"\|egrep -v \"dm\|identifier\"");
    $mipaddr = $ip;
    $mnicmac = `arp -a $ip | awk '{print \$4}'`;
    foreach my $mpdisk (@madisks){
        $mpdisk =~ s/Disk //;
        ($mpdisks,$mtdisksize) = (split(' ',$mpdisk))[0,1]; 
        ($mpdisks)  = $mpdisk =~ m/(naa.*?)\s/;
        $mpdisks    =~ s/:$//;
        # ($mtdisksize) = $disk  =~ m/\s(\d+.*MB)\s/;  
    } 
    print_note "Gathering System Information \n Hardware info : $hwinfo\n";
    open (MINFO, ">" ,$hwinfo) or die "Could not open File $hwinfo";
       print MINFO $ssh->capture("esxcfg-info -w");
    close (MINFO);
    
    open (MINFO, "$hwinfo") or die "Unable to Open File $hwinfo";
    my @hwdata = <MINFO>;
        foreach my $line (@hwdata){
            if ($line =~ m/Product Name/) {
                chomp($line);
                $mmodule = (split('\.',$line))[-1];
                ($mtype) = $mmodule =~ m/(\[.*\])/;
                $mmodule =~ s/\-\[.*//g;
                $mtype =~ s/[\[\]]//g;
                
            }elsif ($line =~ m/^   \|(\-*)Vendor Name/){
                $mvendor = (split('\.',$line))[-1];  
                chomp($mvendor);
            }elsif ($line =~ m/Serial Number/){
                $mserial = (split('\.',$line))[-1];  
                chomp($mserial);
            }elsif (($line =~ m/Num Packages/) || ($line =~ m/Num Cores/)) {
                if ($line =~ m/Num Packages/){ 
                    $mncpus = (split('\.',$line))[-1];
                    chomp($mncpus);
                }
                if ($line =~ m/Num Cores/){ 
                    $mncpuc = (split('\.',$line))[-1];
                    chomp($mncpuc);
                }
            }elsif ($line =~ m/Physical Mem(\.+)/){
                $mmemsize = (split('\.',$line))[-1];
                $mmemsize =~ s/\s\w+//g;
                chomp($mmemsize);
                $mmemsize = int($mmemsize /1024/1024);
                $mmemsize .= "MB";
            } 
        }
    close(MINFO);
    system("rm -f $hwinfo");
    print_results();
    }else{
        print "Port is Close on " . $ip  ;
    }
    
}
sub vm_check($$$){

    my $user    =   shift;
    my $pass    =   shift;
    my $ip      =   shift;
    
    print "Checking VM Mahine Version.\n";
    my  $socket =   new IO::Socket::INET->new(PeerAddr => $ip, PeerPort => '22', Proto => 'tcp' , timeout => 1);

    if ($socket){
        my  $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>1 );
            if ($ssh->error){ 
                print "Unable to connect to remote host :" .$ip." : " . $ssh->error;
                last;
            }
                esxi_info($user,$pass,$ip);    
    }else{
        print "Port is Close\n";
    }
}
sub linux_info($$$){

    my $user    =   shift;
    my $pass    =   shift;
    my $ip      =   shift;
    $mipaddr = $ip ;
    my  $socket =   new IO::Socket::INET->new(PeerAddr => $ip, PeerPort => '22', Proto => 'tcp' , timeout => 1);
    if ($socket){
        my  $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>1 );
            if ($ssh->error){ 
                print_error "Unable to connect to remote host :" . $ssh->error;
                last;
            }
        
        my @mvendor = $ssh->capture("dmidecode \| grep \"Product\""); 
        foreach $mvendor (@mvendor){
            if ($mvendor =~ /VMware Virtual Platform/mg){
                print_note "This Machine is VMware\n";
                return;
            }
        }
        if ($ssh->error) { 
            print_error "Unable to execute GLPI on $ip";
        }
        $mhostname = $ssh->capture("hostname -s"); # Get Host name
        chomp($mhostname);
##################################################
        if ( $ssh->test(ls => "/etc/redhat-release")){
            $msoftver  = $ssh->capture("cat /etc/redhat-release");    
        }elsif ( $ssh->test(ls =>"/etc/SuSE-release")){
            $msoftver  = $ssh->capture("cat /etc/SuSE-release | head -n1");
        }elsif ($ssh->test(ls => "/etc/Debian_version")){
            $msoftver = $ssh->capture("cat /etc/Debian_version");
        }else{
            print_error "WARNING: Host $ip, Linux distribution could not be determined. If you \n"
             . "know how, please add the appropriate checks and code for \n"
             . "package listing to this script. You can e-mail the patch or \n"
             . "changes to <meirfi\@il.ibm.com>. Thanks!\n";
            return;
        }
    #my $hwinfo  = "$tmp$mhostname.hwinfo.log";
    my $hwinfo  = "/tmp/$mhostname.hwinfo.log";
    unlink $hwinfo;
    #print "Opening log file on $ip\n";
    open (FH, ">" ,$hwinfo) or die "Could not open File $hwinfo";
        my $cap_dmi = "dmidecode \| grep \"System Information\" -A6";
        print FH $ssh->capture($cap_dmi);
        #print MINFO $ssh->capture('dmidecode | grep "System Information" -A6');
        #print FH $ssh->capture("dmidecode \| grep \"System Information\" -A6 >/dev/null");
    close FH or die;

    open (MINFO, "$hwinfo") or die "Unable to Open File $hwinfo";
        my @hwdata = <MINFO>;
        foreach my $hwdata (@hwdata) {
            if ($hwdata =~ /Manufacturer/m){
                $mvendor = (split(':', $hwdata))[-1];
                $mvendor =~ s/^\s+//;
                chomp($mvendor);
            }elsif ($hwdata =~ /Product Name/m){
                $mmodule = (split(':',$hwdata))[-1];
                ($mtype) = $mmodule =~ m/(\[.*\])/;
                $mmodule =~ s/\-\[.*//g;
                $mmodule =~ s/^\s+(IBM)//;
                $mmodule =~ s/^\s+//;
                $mtype =~ s/[\[\]]//g;
                #$mtype =~ s/^\s+//;
                chomp($mmodule,$mtype);
            }elsif ($hwdata =~ /Serial Number/m){
                $mserial = (split(':',$hwdata))[-1];  
                $mserial =~ s/^\s+//;
                chomp($mserial);
            }
            
        }
    close(MINFO);

    #system("rm -f $hwinfo");
    $mncpus = $ssh->capture("cat /proc/cpuinfo \|grep \"physical id\"\|uniq \| wc -l");
    $mncpuc = $ssh->capture("cat /proc/cpuinfo \| egrep \"processor\"\|wc -l");    
    $mnicmac = $ssh->capture("ifconfig \|grep -B1 $ip \| awk \'\/HWaddr\/ {print \$5}\'");
        #$mnicmac = $ssh->capute("ifconfig \|grep -B1 $ip \| awk \'\/HWaddr\/ \{print $5\}\');
        #print_info ("MAC Address is : " .$mnicmac ."\n");
    @mnicsinfo = $ssh->capture("lspci \| grep -i Ethernet");
    $mnics  = scalar(@mnicsinfo); 
    $mmemsize = $ssh->capture("cat /proc/meminfo\|grep MemTotal");
    ($mmemsize) = (split(':', $mmemsize))[1];
    $mmemsize =~ s/^\s+//;
    ($mmemsize) = $mmemsize =~ m/(\d+.)/;
    $mmemsize = int($mmemsize /1024);
    $mmemsize .= " MB";
    @madisks = $ssh->capture("fdisk -l 2> /dev/null \| grep \"^Disk\"\|egrep -v \"dm\|identifier\"");
    foreach my $mpdisk (@madisks){
        $mpdisk =~ s/Disk //;
        ($mpdisks,$mtdisksize) = (split(' ',$mpdisk))[0,1]; 
        $mpdisks =~ s/:$//;
    }
    chomp($mhostname,$mipaddr,$msoftver,$mvendor,$mmodule,$mtype, $mserial,$mncpus,$mncpuc,$mnics,$mmemsize,$mpdisks,$mtdisksize,$mnicmac);
    print_results();
    
    }else{
        print_info "Port close on : " . $ip . "\n";
        return;
    }
}
sub vmware_info($$$){

    my $user    =   shift;
    my $pass    =   shift;
    my $ip      =   shift;
    $mipaddr = $ip ;
    my  $socket =   new IO::Socket::INET->new(PeerAddr => $ip, PeerPort => '22', Proto => 'tcp' , timeout => 1);
    if ($socket){
        my  $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>1 );
            if ($ssh->error){ 
                print_error "Unable to connect to remote host :" . $ssh->error;
                return;
            }
        
        my @mvendor = $ssh->capture("dmidecode \| grep \"Product\""); 
        $mhostname = $ssh->capture("hostname -s"); # Get Host name
        chomp($mhostname);
##################################################
        if ( $ssh->test(ls => "/etc/redhat-release")){
            $msoftver  = $ssh->capture("cat /etc/redhat-release");    
        }elsif ( $ssh->test(ls =>"/etc/SuSE-release")){
            $msoftver  = $ssh->capture("cat /etc/SuSE-release | head -n1");
        }elsif ($ssh->test(ls => "/etc/issue")){
            $msoftver = $ssh->capture("cat /etc/issue");
        }else{
            print_error "WARNING: Host $ip, Linux distribution could not be determined. If you \n"
             . "know how, please add the appropriate checks and code for \n"
             . "package listing to this script. You can e-mail the patch or \n"
             . "changes to <meirfi\@il.ibm.com>. Thanks!\n";
            return;
        }
    #my $hwinfo  = "$tmp$mhostname.hwinfo.log";
    my $hwinfo  = "/tmp/$mhostname.hwinfo.log";
    unlink $hwinfo;
    #print "Opening log file on $ip\n";
    open (FH, ">" ,$hwinfo) or die "Could not open File $hwinfo";
        my $cap_dmi = "dmidecode \| grep \"System Information\" -A6";
        print FH $ssh->capture($cap_dmi);
        #print MINFO $ssh->capture('dmidecode | grep "System Information" -A6');
        #print FH $ssh->capture("dmidecode \| grep \"System Information\" -A6 >/dev/null");
    close FH or die;

    open (MINFO, "$hwinfo") or die "Unable to Open File $hwinfo";
        my @hwdata = <MINFO>;
        foreach my $hwdata (@hwdata) {
            if ($hwdata =~ /Manufacturer/m){
                $mvendor = (split(':', $hwdata))[-1];
                $mvendor =~ s/^\s+//;
                chomp($mvendor);
            }elsif ($hwdata =~ /Product Name/m){
                $mmodule = (split(':',$hwdata))[-1];
                ($mtype) = $mmodule =~ m/(\[.*\])/;
                $mmodule =~ s/\-\[.*//g;
                $mmodule =~ s/^\s+(IBM)//;
                $mmodule =~ s/^\s+//;
                $mtype =~ s/[\[\]]//g;
                #$mtype =~ s/^\s+//;
                chomp($mmodule,$mtype);
            }elsif ($hwdata =~ /Serial Number/m){
                $mserial = (split(':',$hwdata))[-1];  
                $mserial =~ s/^\s+//;
                chomp($mserial);
            }
            
        }
    close(MINFO);

    #system("rm -f $hwinfo");
    $mncpus = $ssh->capture("cat /proc/cpuinfo \|grep \"physical id\"\|uniq \| wc -l");
    $mncpuc = $ssh->capture("cat /proc/cpuinfo \| egrep \"processor\"\|wc -l");    
    $mnicmac = $ssh->capture("ifconfig \|grep -B1 $ip \| awk \'\/HWaddr\/ {print \$5}\'");
        #$mnicmac = $ssh->capute("ifconfig \|grep -B1 $ip \| awk \'\/HWaddr\/ \{print $5\}\');
        #print_info ("MAC Address is : " .$mnicmac ."\n");
    @mnicsinfo = $ssh->capture("lspci \| grep -i Ethernet");
    $mnics  = scalar(@mnicsinfo); 
    $mmemsize = $ssh->capture("cat /proc/meminfo\|grep MemTotal");
    ($mmemsize) = (split(':', $mmemsize))[1];
    $mmemsize =~ s/^\s+//;
    ($mmemsize) = $mmemsize =~ m/(\d+.)/;
    $mmemsize = int($mmemsize /1024);
    $mmemsize .= " MB";
    @madisks = $ssh->capture("fdisk -l 2> /dev/null \| grep \"^Disk\"\|egrep -v \"dm\|identifier\"");
    foreach my $mpdisk (@madisks){
        $mpdisk =~ s/Disk //;
        ($mpdisks,$mtdisksize) = (split(' ',$mpdisk))[0,1]; 
        $mpdisks =~ s/:$//;
    }
    chomp($mhostname,$mipaddr,$msoftver,$mvendor,$mmodule,$mtype, $mserial,$mncpus,$mncpuc,$mnics,$mmemsize,$mpdisks,$mtdisksize,$mnicmac);
    print_results();
    
    }else{
        print_info "Port close on : " . $ip . "\n";
        return;
    }
}

sub rtc_info($$$){

    my $user    =   shift;
    my $pass    =   shift;
    my $ip      =   shift;
    $mipaddr = $ip ;
    my  $socket =   new IO::Socket::INET->new(PeerAddr => $ip, PeerPort => '26', Proto => 'tcp' , timeout => 1);
    if ($socket){
        my  $ssh = Net::OpenSSH->new("$user:$pass\@$ip:26", timeout=>1 );
            if ($ssh->error){ 
                print_error "Unable to connect to remote host :" . $ssh->error;
                return;
            }
        
        my @mvendor = $ssh->capture("dmidecode \| grep \"Product\""); 
        foreach $mvendor (@mvendor){
            if ($mvendor =~ /VMware Virtual Platform/mg){
                print_note "This Machine is VMware\n";
                return;
            }
        }
        if ($ssh->error) { 
            print_error "Unable to execute GLPI on $ip";
        }
        $mhostname = $ssh->capture("hostname -s"); # Get Host name
        chomp($mhostname);
##################################################
        $msoftver = check_os($ssh);

    my $hwinfo  = "/tmp/$mhostname.hwinfo.log";
    unlink $hwinfo;
    open (FH, ">" ,$hwinfo) or die "Could not open File $hwinfo";
        my $cap_dmi = "dmidecode \| grep \"System Information\" -A6";
        print FH $ssh->capture($cap_dmi);
    close FH or die;

    open (MINFO, "$hwinfo") or die "Unable to Open File $hwinfo";
        my @hwdata = <MINFO>;
        foreach my $hwdata (@hwdata) {
            if ($hwdata =~ /Manufacturer/m){
                $mvendor = (split(':', $hwdata))[-1];
                $mvendor =~ s/^\s+//;
                chomp($mvendor);
            }elsif ($hwdata =~ /Product Name/m){
                $mmodule = (split(':',$hwdata))[-1];
                # ORIG ($mtype) = $mmodule =~ m/(\[.*\])/;
                ($mtype) = $mmodule =~ m/\[(.*)\]/;
                $mmodule = leading_trailing($mmodule);
                chomp($mmodule);
            }elsif ($hwdata =~ /Serial Number/m){
                $mserial = (split(':',$hwdata))[-1];  
                $mserial =~ s/^\s+//;
                chomp($mserial);
            }
        }

    close(MINFO);

    #system("rm -f $hwinfo");
    $mncpus = $ssh->capture("cat /proc/cpuinfo \|grep \"physical id\"\|sort \| uniq \| wc -l");
    $mncpuc = $ssh->capture("cat /proc/cpuinfo \| egrep \"processor\"\|tail -1");
    $mnicmac = $ssh->capture("ifconfig \|grep -B1 $ip \| awk \'\/HWaddr\/ {print \$5}\'");
    ($mncpuc) = (split(":",$mncpuc))[-1];    
    $mncpuc += "1";
#        print_info ("NUMBER OF CORS : $mncpuc");
    @mnicsinfo = $ssh->capture("lspci \| grep -i Ethernet");
    $mnics  = scalar(@mnicsinfo); 
    $mmemsize = $ssh->capture("cat /proc/meminfo\|grep MemTotal");
    ($mmemsize) = (split(':', $mmemsize))[1];
    $mmemsize =~ s/^\s+//;
    ($mmemsize) = $mmemsize =~ m/(\d+.)/;
    $mmemsize = int($mmemsize /1024);
    $mmemsize .= " MB";
    #$madisks = $ssh->capture("fdisk -l 2> /dev/null \| grep \"^Disk\"\|egrep -v \"dm\|identifier\"");
    @madisks = $ssh->capture("fdisk -l 2> /dev/null \| grep \"^Disk\"\|egrep -v \"dm\|identifier\"");
    #@madisks = $ssh->capture("cat /sys/block/sd?/size");
    ($mpdisks,$mtdisksize) = ();
    foreach my $mpdisk (@madisks){
        $mpdisk =~ s/Disk //;
        $mpdisk =~ s/,.*//;
        $mpdisk =~ s/://;
        $mpdisk = leading_trailing($mpdisk);
        if ($mpdisk =~ m/(\/\w.+\/\w+)\s(\d+.*)/) {
            if ((!defined $mpdisks) && (!defined $mtdisksize)) {
                $mpdisks    = "$1,";
                $mtdisksize = "$2,";
            } else {
                $mpdisks    .= "$1";
                $mtdisksize .= "$2";
            }
        }
    }
    print_results();
    
    }else{
        print_info "Port close on : " . $ip . "\n";
        return;
    }
}
sub check_os {
        my $ssh = shift;
        if ( $ssh->test(ls => "/etc/redhat-release")){
            $msoftver  = $ssh->capture("cat /etc/redhat-release");    
            return $msoftver;
        }elsif ( $ssh->test(ls =>"/etc/SuSE-release")){
            $msoftver  = $ssh->capture("cat /etc/SuSE-release | head -n1");
            return $msoftver;
        }elsif ($ssh->test(ls => "/etc/Debian_version")){
            $msoftver = $ssh->capture("cat /etc/Debian_version");
            return $msoftver;
        }elsif ($ssh->test(ls => "/etc/base-release")){
            $msoftver = $ssh->capture("cat /etc/base-release");
            return $msoftver;
        }elsif ($ssh->test(ls => "/etc/issue")){
            $msoftver = $ssh->capture("cat /etc/issue");
            return $msoftver;
        }elsif ($ssh->pipe_out("version")){
            $msoftver = $ssh->capture("version");
            print "This is ONTAP Sotrage \n";
            print_info " Storage " . $ssh->capture("version");
            exit;
        }else{
            print_error "WARNING : Linux distribution could not be determined. If you \n"
             . "know how, please add the appropriate checks and code for \n"
             . "package listing to this script. You can e-mail the patch or \n"
             . "changes to <meirfi\@il.ibm.com>. Thanks!\n";
            $msoftver = "None";    
            return $msoftver;
        }
    
}
sub storage_info($$$){

    my $user    =   shift;
    my $pass    =   shift;
    my $ip      =   shift;
    $mipaddr = $ip ;
    my  $socket =   new IO::Socket::INET->new(PeerAddr => $ip, PeerPort => '22', Proto => 'tcp' , timeout => 20);
    if ($socket){
        my  $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>20 );
            if ($ssh->error){ 
                print_error "Unable to connect to remote host :" . $ssh->error;
                last;
            }
        #my $mvendor = $ssh->capture("version"); 
        $mhostname = $ssh->capture("hostname"); 
        

        chomp($mhostname);
##################################################
    my $hwinfo  = "/tmp/$mhostname.hwinfo.log";
    print "Opening log file on : $mhostname\n";
    open (FH, ">" ,$hwinfo) or die "Could not open File $hwinfo";
        my $cap_dmi = "sysconfig -a";
         $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>1 );
        print FH $ssh->capture($cap_dmi);
    close FH or die;
   print "File Name : " . $hwinfo . "\n"; 
    open (MINFO, "$hwinfo") or die "Unable to Open File $hwinfo";
        my @hwdata = <MINFO>;
        foreach my $hwdata (@hwdata) {
            chomp($hwdata);
            if ($hwdata =~ /Data ONTAP/m){
                $msoftver = (split(':', $hwdata))[0];
            }elsif ($hwdata =~ /Model Name:/m){
                $mmodule = (split(':', $hwdata))[-1];
            }elsif ($hwdata =~ /System ID/m){
                $mserial = (split(':',$hwdata))[-1];  
                ($mserial) = $mserial =~ m/(\d+.*)\s+/;
            }elsif ($hwdata =~ /Processors:/m) {
                $mncpus = (split(':', $hwdata))[-1];
            }
            
        }
    close(MINFO);

    $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>1 );
    my @disk = $ssh->capture("sysconfig");
    foreach my $disk (@disk){
        if ($disk =~ /Disks:/m) { 
           ($mpdisks,$mtdisksize) = (split(':' , $disk))[0,1];
        }
    }
    open (FH, ">" ,$hwinfo) or die "Could not open File $hwinfo";
        my $cap_dmii = "sysconfig";
         $ssh = Net::OpenSSH->new("$user:$pass\@$ip", timeout=>1 );
        print FH $ssh->capture($cap_dmii);
    close FH or die;
        my $info = "$hwinfo.cut";
        system("cat $hwinfo \| grep \"System Board\" -A14 > $info");

    open (DATA, "$info") or die "Unable to Open File $hwinfo";
    my @hdata = <DATA>;
       foreach my $data (@hdata) {
            if ($data =~ /Model Name:/){
                $mmodule = (split(':',$data))[-1];
            }
            elsif ($data =~ /Memory Size:/){
                $mmemsize = (split(':', $data))[-1];
            }

        }
    close(DATA);
    
    print_results();
    
    }else{
        print_info "Port close on : " . $ip . "\n";
        return;
    }
}
#########################################################################################################
##################### Main Run
########################################################################################################

open_log;
print_log "Connecting to Database : " . $dbname ." ";
db_connect($dbname,$dbuser,$dbpass);


foreach my $sig (@sig_ip){
    print_info "#### Starting scanning on Segment : $sig ####\n";
    print_log "\n";
    for (my $ip = 1 ; $ip <= 254 ; $ip++){
    
        my $ipaddr .= $sig.$ip;
        $mhostname = ""; 
        $mipaddr =""; 
        $mserial ="" ;
        $mnicmac = "";
        my $dname;
        my $dns_name    =   gethostbyaddr(inet_aton($ipaddr), AF_INET);
        if (!defined($dns_name) || ($dns_name eq "" )){
            $dns_name = "N/A";
        }
            if ($dns_name ne "N/A"){
                $dname = substr($dns_name , 0 , index($dns_name, "."));
            }else{
                $dname = $dns_name; 
            }
                #my ($dname) = $dns_name =~ /^(\w+).*/; 
                    print_info ("HOSTNAME TEST : " . $dname . " full name : " . $dns_name );
            print_hst("IPADDR : " . $ipaddr . " Hostname : ". $dname);
            if ($dname =~ m/(imm)/){
                printf ("IP : %s , HOSTNAME : %s , HOST TYPE : IMM", $ipaddr,$dname );
                print_info "IP Address : $ipaddr, Host name : $dname, OS Type : imm";
                my $id      =   "USERID";
                my $pass    =   "PASSW0RD";
                print "\n";
            }elsif($dname =~ m/(esx)/){
                printf ("IP : %s , HOSTNAME : %s , HOST TYPE : ESXi", $ipaddr,$dname );
                print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : ESXi";
                $id      =   "root";
                $pass    =   "abcd_1234";
                &esxi_info($id,$pass,$ipaddr);
                print "\n";
            }elsif($dname =~ m/(vm)/) {
                printf ("IP : %s , HOSTNAME : %s , HOST TYPE : VMWare", $ipaddr,$dname );
                print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : VMWare";
                $id      =   "root";
                $pass    =   "a1b2c3";
                &vmware_info($id,$pass,$ipaddr);
                print "\n";
            }elsif (($dname =~ m/(svc)/) || ($dname =~ m/^(rtc)/)){

                printf ("IP : %s , HOSTNAME : %s , HOST TYPE : SVC/V7000", $ipaddr,$dname );
                print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : SVC ";
                $id      =   "root";
                $pass    =   "l0destone";
                &rtc_info($id,$pass,$ipaddr);
                print "\n";
            }elsif($dname =~ m/(aix)/) {
                printf ("IP : %s , HOSTNAME : %s , HOST TYPE : AiX", $ipaddr,$dname );
                print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : AIX";
                $id      =   "root";
                $pass    =   "a1b2c3";
                &aix_info($id,$pass,$ipaddr);
                print "\n";
            }elsif($dname =~ m/(mozes)/) {
                printf ("IP : %s , HOSTNAME : %s , HOST TYPE : ONTAP ", $ipaddr,$dname );
                #printf ("%.5s %05s %02s %02s %4s", "IP : ",$ipaddr, ", Hostname : " , $dname, ", Host Type : Ontap ");
                print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : OnTasp";
                $id      =   "root";
                $pass    =   "abcd_1234";
                #check_os($id,$pass,$ipaddr);
                &storage_info($id,$pass,$ipaddr);
                print "\n";
            }else{
                #print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : Unknow System";
                $id     =   "root";
                #$pass   =   "abcd_1234";
                $pass   =   "a1b2c3";
            #print "checking ssh port\n";
            my  $socket =   new IO::Socket::INET->new(PeerAddr => $ipaddr, PeerPort => '22', Proto => 'tcp' , timeout => 1);
                if ($socket){
                    my  $ssh = Net::OpenSSH->new("$id:$pass\@$ipaddr", timeout=>1);
                    if ($ssh->error){ 
                        printf ("IP : %s , HOSTNAME : %s , HOST TYPE : Unknown OS ", $ipaddr,$dname );
                        print_error "IP Address : $ipaddr, Host name : $dns_name , OS Type : My be Linux - ERROR Unable to SSH";
                        print "\n";
                        next;
                    }else{
                        #print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : Linux";
                        my $mf = $ssh->capture("dmidecode | grep \"Manufacturer: VM\"");
                        if ($mf =~ m/VMware/) {
                            #print_info "HW Type : VMware";
                            printf ("IP : %s , HOSTNAME : %s , HOST TYPE : VMWare", $ipaddr,$dname );
                            print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : Linux , HW Type : VMware ";
                            &vmware_info($id,$pass,$ipaddr);
                            print "\n";
                            next;
                        }else{
                            printf ("IP : %s , HOSTNAME : %s , HOST TYPE : LiNUX", $ipaddr,$dname );
                            &linux_info($id,$pass,$ipaddr);
                            # &esxi_info($id,$pass,$ipaddr);
                            print "\n";
                        }
                    }
            }else{
                print_info "IP Address : $ipaddr, Host name : $dns_name , OS Type : Windows";
            }
        }
    }
}


__END__

#HOSTNAME           (wlp01)
#MACHINE_VENDOR     (IBM,HP,etc) 
#MACHINE_SERIAL     (06EEAF0)




