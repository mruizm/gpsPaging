#!/usr/bin/perl
use strict;
use warnings;
use lib "/home/rumarco/usr/lib64/perl5";

my $line;
my $dispatched_ticket_id_body;
my $dispatched_ticket_workgroup;
my $dispatched_ticket_id;
my $ticket_dispatched_prio;
my @EON_Alert_array = ();
my $complete_EON_WG;
my $is_EON_complete = 0;

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
    $is_EON_complete = 0;
    if (/^Subject:\s(EON[\s|\w\d|-]+[\w\d]+\sEscalation\sAlert)\s-\s([\d]+)/ .. /View more details/)
    {
		my $EON_Subject = $1;
        my $EON_Id = $2;       
        if (/^Event & Esc Level.*/ .. /@[\d]+:[\d]+/)
        {
            my $EON_Wg_Line =  $_;
            if (/^Message:/ .. /@[\d]+:[\d]+/)
            {
                chomp($EON_Wg_Line);
            	$complete_EON_WG = $complete_EON_WG.$EON_Wg_Line;
        	}
        	if ($EON_Wg_Line =~ m/@[\d]+:[\d]+/)
        	{
        		$complete_EON_WG = $complete_EON_WG."\n";
        		$is_EON_complete = 1;        		        		
        	}
        	if($is_EON_complete == 1)
    		{
    			$complete_EON_WG =~ s/=|Message:|Tkt:|\s\s//g;
    			#print "$complete_EON_WG\n";
    			$complete_EON_WG =~ m/([\w\d|:|\s|\.]+)\/([\w\d|:|\s|\.]+)\/([\w\d|:|\s|\.]+)\/([\w\d|:|\s|\.]+)\/([\w\d|:|\s|\.]+)\/([\w\d|:|\s|\.]+)\/([\w\d|:|\s|\.]+)\/([\w\d|:|\s|\.|@]+)/;
    			my $EON_problem  = $6;
    			my $EON_team = $7;
    			$EON_problem =~ s/Prob://gi;
    			$EON_team =~ s/Esc.Team://gi;
    			print "EON Escalation $EON_Id: $EON_problem $EON_team\n";
   			}
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
#print "$complete_EON_WG\n";
