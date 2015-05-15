#! /usr/bin/perl 

#use warnings;
use strict;

sub build_HashArray;
sub collect_NetStats;
sub collect_TCPRetrans;
sub collect_TCPSegs;
sub collect_IOStats;
sub collect_VMStats;
sub collect_CPUStats;

$SIG{INT} = \&signal_handler; 
$SIG{TERM} = \&signal_handler; 

my @data = ();
my $now = `date +%s`;
my $env = $ENV{'NETFLIX_ENVIRONMENT'}; # test or prod
my $region = $ENV{'EC2_REGION'};
my $host = $ENV{'EC2_INSTANCE_ID'};  # ex: i-c3a4e33d 
my $server = "cluster.$ENV{'NETFLIX_APP'}";   # ex:  abcassandra_2
my $carbon_server; 
my $interval = 5; 

# I have setup two servers to store metrics. One is in production and other is in test
if ( $env =~ /prod/) {
 $carbon_server = "abyss.$region.prod.netflix.net";
 }
else {
 $carbon_server = "abyss.$region.test.netflix.net";
 }

# Run at lowest priority possible to avoid competing for cpu cycles with the workload
#setpriority(0,$$,19);

# Make sure you nc installed on the system

# Open a connection to the carbon server where we will be pushing the metrics
open(GRAPHITE, "| nc -w 15 $carbon_server 7001") || die print "failed to send data: $!\n";

# Capture metrics every 5 seconds until interrupted.
while (1) {

# graphite metrics are sent with date stamp 
 $now = `date +%s`;

# collect metrics

collect_NetStats;       # Net stats 
collect_TCPRetrans;     # TCP stats 
collect_TCPSegs;	# TCP segments
collect_IOStats;	# io stats
collect_CPUStats;	# cpu stats
collect_VMStats;	# vm stats

# Ship Metrics to carbon server ----

 #print @data; # For Testing only 
 #print "\n------\n"; # for Testing only
 print GRAPHITE  @data;  #  Dump metrics to carbon server
 @data=();  	# Initialize the array for next set of metrics

  sleep $interval ;  #Default interval is 5 seconds
}

# ----------------------- All subroutines -----------------

sub signal_handler {
  die "Caught a signal $!";
}

sub build_HashArray {
  my ($keys, $values) = @_;
  my %sub_hash;
  foreach my $key (@$keys){
   foreach my $value (@$values){
    push (@{$sub_hash{$key}}, $value);
   }
  }
  return %sub_hash;
 }
		
sub collect_NetStats {
 my @stats;
 # Net packets and bytes IN and OUT
 open (INTERFACE, "cat /proc/net/dev |")|| die print "failed to get data: $!\n";
  while (<INTERFACE>) {
  next if (/^$/ || /^Inter/ || /face/) ;
  s/:/ /g;
  @stats = split;
  push @data, "$server.$host.system.interface.$stats[0].rxbytes $stats[1] $now\n";
  push @data, "$server.$host.system.interface.$stats[0].rxpackets $stats[2] $now\n";
  push @data, "$server.$host.system.interface.$stats[0].txbytes $stats[9] $now\n";
  push @data, "$server.$host.system.interface.$stats[0].txpackets $stats[10] $now\n";
 }
 close(INTERFACE);
}

sub collect_TCPRetrans {
  my @stats;
  open (TCP, "cat /proc/net/netstat |")|| die print "failed to get data: $!\n";
  while (<TCP>) {
  next if ( /SyncookiesSent/ || /Ip/);
  @stats = split;
  push @data, "$server.$host.system.tcp.ListenDrops $stats[21] $now\n";
  push @data, "$server.$host.system.tcp.TCPFastRetrans $stats[45] $now\n";
  push @data, "$server.$host.system.tcp.TCPSlowStartRetrans $stats[47] $now\n";
  push @data, "$server.$host.system.tcp.TCPTimeOuts $stats[48] $now\n";
  push @data, "$server.$host.system.tcp.TCPBacklogDrop $stats[75] $now\n";
 }
close(TCP);
}

sub collect_TCPSegs {
  my @stats;
 # Tcp: RtoAlgorithm RtoMin RtoMax MaxConn ActiveOpens PassiveOpens AttemptFails EstabResets CurrEstab InSegs OutSegs RetransSegs 
 # Tcp: 1 200 120000 -1 4828 4261 5 5 380 515264340 1324251168 2482 0 25 0
  open (TCP, "cat /proc/net/snmp |")|| die print "failed to get data: $!\n";
  while (<TCP>) {
   next if (!/Tcp/);
   next if (/RtoAlgo/);
   @stats = split; 
   push @data, "$server.$host.system.tcp.ActiveOpens $stats[5] $now\n";
   push @data, "$server.$host.system.tcp.PassiveOpens $stats[6] $now\n";
   push @data, "$server.$host.system.tcp.EstabRsts $stats[8] $now\n"; 
   push @data, "$server.$host.system.tcp.InSegs $stats[10] $now\n";
   push @data, "$server.$host.system.tcp.OutSegs $stats[11] $now\n";
   push @data, "$server.$host.system.tcp.RetransSegs $stats[12] $now\n";
   push @data, "$server.$host.system.tcp.OutRst $stats[14] $now\n";  
 }
close(TCP);
}

sub collect_IOStats {
  my @stats;
  open (IOSTAT, "cat /proc/diskstats |")|| die print "failed to get data: $!\n";
  while (<IOSTAT>) {
  next if (/^$/ || /loop/) ;
  @stats = split;
  push @data, "$server.$host.system.io.$stats[2].ReadIOPS $stats[3] $now\n";
  push @data, "$server.$host.system.io.$stats[2].WriteIOPS $stats[7] $now\n";
  push @data, "$server.$host.system.io.$stats[2].ReadSectors  $stats[5]  $now\n";
  push @data, "$server.$host.system.io.$stats[2].WriteSectors $stats[9]  $now\n";
  push @data, "$server.$host.system.io.$stats[2].ReadTime $stats[6] $now\n";
  push @data, "$server.$host.system.io.$stats[2].WriteTime $stats[10] $now\n";
  push @data, "$server.$host.system.io.$stats[2].QueueSize $stats[13] $now\n";
  push @data, "$server.$host.system.io.$stats[2].Utilization $stats[12] $now\n";
 } 
close(IOSTAT);

}

sub collect_VMStats {
 my @Array;
 my @stats;
 my $used;
 my $free_cached;
 my $free_unused;

 open(VMSTAT, "head -4 /proc/meminfo |")|| die print "failed to get data: $!\n";
 while (<VMSTAT>) {
 next if (/^$/);
 s/://g;   # trim ":"
 @stats = split;
 push @Array,$stats[1];
 }
close (VMSTAT);
 $free_cached = $Array[2] + $Array[3];
 $free_unused = $Array[1];
 $used = $Array[0] - $free_cached - $free_unused;

 push @data, "$server.$host.system.mem.free_cached $free_cached $now\n";
 push @data, "$server.$host.system.mem.free_unused $free_unused $now\n";
 push @data, "$server.$host.system.mem.used $used $now\n";
}

sub collect_CPUStats {
 my %cpuhash;
 my @stats;
 my $key;
 my $values;
 my $user;
 my $sys;
 my $idle;
 my $intr;

 open(MPSTAT, "cat /proc/stat |")|| die print "failed to get data: $!\n";
 while (<MPSTAT>) {
 next if (/^$/ || /^intr/ || /^btime/ || /^processes/ || /^softirq/) ;
 if ( /^cpu/ ) {
  ($key, $values) = split;
  @stats = split, $values;
  shift(@stats);
  $cpuhash{$key} = [ @stats ];
  }
 else {  # also needs to collect running and blocked processes
  @stats = split;
  push @data, "$server.$host.system.CPU.$stats[0] $stats[1] $now\n";
 } 
 }
close(MPSTAT);
 foreach $key (keys %cpuhash){
  $user = $cpuhash{$key}[0] + $cpuhash{$key}[1];
  $sys = $cpuhash{$key}[2];
  $idle = $cpuhash{$key}[3] + $cpuhash{$key}[4];
  $intr = $cpuhash{$key}[5] + $cpuhash{$key}[6];
  
  push @data, "$server.$host.system.CPU.$key.user $user $now\n";
  push @data, "$server.$host.system.CPU.$key.sys $sys $now\n";
  push @data, "$server.$host.system.CPU.$key.idle $idle $now\n";
  push @data, "$server.$host.system.CPU.$key.intr $intr $now\n";
 }
}
