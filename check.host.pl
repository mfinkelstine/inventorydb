#!/usr/bin/perl -w

use strict;
use warnings;
### Modules #######################

use Socket;
use IO::Socket::INET;
use Net::OpenSSH;

#my @port_list = ( "26");
my @port_list = ("22", "26");
my %up = (  "root_a",     "a1b2c3",
            "root_b",     "abcd_1234",
            "root_c",     "l0destone",
            "USERID_d",   "PASSW0RD");
my @user_pass = (
        [ 'root',       'a1b2c3'    ],
        [ 'root',       'abcd_1234' ],
        [ 'root',       'l0destone' ],
        [ 'USERID',    'PASSW0RD'  ] 
        );

my @sig_ip  =   ("9.151.184.");
my $parent = 0;
my $host_user;
my $host_pass;
my $host_port;

#my @sig_ip  =   ("9.151.184.", "9.151.185.");

sub open_ssh_connection {
    my $ip      = shift;
    my $host    = shift;    
    my $socket;
    my @p;
    #print "Host Name : $host, $ip ";
    #print "\nPort Checking to : $host ";

    open my $stderr_fh, '>>', "/tmp/$host.err" or print "unable to open file $host.err\n";
    open my $stdout_fh, '>>', "/tmp/$host.out" or print "unable to open file $host.err\n";
    
    foreach my $port (@port_list) {
        $socket = IO::Socket::INET->new( 
                  PeerAddr => "$ip",
                  PeerPort => "$port", 
                  Proto    => 'tcp');
        if ($socket) {
            push (@p, $port);  
            close($socket);
        }
    }
    #print "Total open Ports : " .scalar(@p). " ports : " . join(",", @p) . " ";

#### Checking open port foreach host ##################################################################################
    foreach $host_port (@p) {
#### Open Socket to Host ##############################################################################################
        $socket = IO::Socket::INET->new( 
                  PeerAddr => "$ip",
                  PeerPort => "$host_port", 
                  Proto    => 'tcp',
                  default_stderr_fh => $stderr_fh,
                  default_stdout_fh => $stdout_fh);

                foreach my $up (@user_pass) {
                    $host_user = $up->[0];
                    $host_pass = $up->[1];
                    my  $ssh = Net::OpenSSH->new("$host_user:$host_pass\@$ip:$host_port", async => 1, default_ssh_opts => ['-oConnectionAttempts=6'],timeout=>8);
                    #my  $ssh = Net::OpenSSH->new("$user:$up{$u}\@$ip:$port", default_ssh_opts => ['-oConnectionAttempts=6'],timeout=>8);
                    if (!$ssh->error){ 
                        #printf ("%10s", "return SSH -> $ssh ");
                        return($ssh,$host_user);
                    }
                }
            close($socket);
            print "\n";   #close($socket);
    }
}

sub _getDistroData {
    my $ssh     = shift;
    my $user    = shift;
    if ($user eq "USERID") {
        return;
    }
    if (!$ssh) {
        print "$ssh not connected ";
    }
    #### Distro List ############
    my @distributions = (
        [ 'cat /etc/vmware-release',    'VMWare',   '([\d.]+)',         '%s' ],
        [ 'cat /etc/debian_version',    'Debian',   '(.*)',             'Debian GNU/Linux %s'], 
        [ 'cat /etc/fedora-release',    'Fedora',   'release ([\d.]+)', '%s' ],
        [ 'cat /etc/centos-release',    'CentOS',   'release ([\d.]+)', '%s' ],
        [ 'cat /etc/redhat-release',    'RedHat',   'release ([\d.]+)', '%s' ],
        [ 'cat /etc/SuSE-release',      'SuSE',     '([\d.]+)',         '%s' ],
        [ 'cat /etc/base-release',      'SVC',      '([\d.]+)'        , '%s' ],
        [ 'vpd imm',                'IMM',      '([\d.]+)'        , '%s' ],
        [ 'version',                'NetApp',      '([\d.]+)'        , '%s' ],
        );

    foreach my $distro (@distributions) {
        my $dist_file   = $distro ->[0];
        my $name        = $distro ->[1];
        my $regexp      = $distro ->[2];
        my $template    = $distro ->[3];
            if (!$ssh) {
                print "ERROR !!! \n" ; 
            }
            if ( $ssh->test(ls => $dist_file)){
        
                print "MOSHE\n";
                my ($line,$out) = $ssh->capture2("cat $dist_file");
                my ($release, $version);
                    if ($line) {
                        $release   = sprintf $template, $line;
                        #   print "RELEASE : " . $release ."\n";
                        ($version) = $line =~ /$regexp/;
                        chomp($version);
                        print "Release Name : " .$name . " Version : " .$version."\n"; 
                    } else {
                        $release = $template;
                        chomp($release);
                        print "Release : " .$release."\n ";
                    }
            }else{ print "ERROR unable to get status \n";

            }
    }
}
sub do_scan { 
    foreach my $sig (@sig_ip){
        print "#### Starting scanning on Segment : $sig ####\n";
            for (my $ip = 24 ; $ip <= 35 ; $ip++){
                my $ipaddr      .= $sig.$ip;
                my $h           =   inet_aton("$ipaddr");
                my $dns_name    =   gethostbyaddr($h, AF_INET);
                if (!$dns_name){
                    $dns_name = "Unknown";
                }
                print "Host name : " . $dns_name . " IP : " . $ipaddr . " Status : " ;
                my ($ssh,$user) = open_ssh_connection($ipaddr,$dns_name);
                if (!$ssh) {
                    print "ERROR: Unable to connect\n";
                }else{
                    if (!$ssh) { 
                        print "Connection Died";
                    }
                    _getDistroData($ssh,$user);
                    print " \n";
                }
            }
    }
}
do_scan();
