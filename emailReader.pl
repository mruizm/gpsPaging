#!/usr/bin/perl
use strict;
use warnings;
use lib "/home/rumarco/usr/lib64/perl5";

my $line;
my $dispatched_ticket_id_body;
my $dispatched_ticket_workgroup;
my $dispatched_ticket_id;
my $ticket_dispatched_prio;

my $FILE = '/var/spool/mail/rumarco';
open (INFILE, $FILE) || die "Not able to open the file: $FILE \n";
while (<INFILE>)
{
	my $line = $_;
	chomp($line);
        
    if ($line =~ m/^Subject:\s([\w|\-|\s|\d]+\s:\s(N-IM[\d|-]+)\s\(.+\)\s-\s(TTR\s[\w|\d|-|\s]+))/)
    {
      	print "ALERT: $1\n";        	
    }
    if ($line =~ m/^Subject:\s([\w|\-|\s|\d]+\s:\s(N-IM[\d|-]+)\s(\(.+\))\s-\sDispatched)/)
    {
		$dispatched_ticket_id = $2;
		$ticket_dispatched_prio = $3;
		#print "ALERT: $1\n";
    }
    if ($line =~ m/(^N-IM[\d|-]+)\shas been\sdispatched\sto\sassignment\sgroup\s?([\w\d|-]+)/)
    {
		$dispatched_ticket_id_body = $1;
		$dispatched_ticket_workgroup = $2;
		if ($dispatched_ticket_id eq $dispatched_ticket_id_body)
		{
			print "ALERT: Incident $1 $ticket_dispatched_prio assigned to $2\n";
		}
    }        
    ##### FOR DTV PAGING #####
    #if ($line =~ m/From\snoreply@[\w\d|.]+\s+[\w\d|\s|:]+[\d]+$/)
    if (/From\snoreply@[\w\d|.]+\s+[\w\d|\s|:]+[\d]+$/ .. /Status: O/)
    {
    	if ($line =~ m/Subject:\sOpenView:\sFrom:([\w\d|:|\s|+|?.]+)/)
        {
 			print "$1\n";
        }        	
	}
}    
er file contents here
