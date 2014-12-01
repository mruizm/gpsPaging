#!/usr/bin/perl
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# File: 		enoteProcessingEmail.pl
# Description: 	Script that processes the incoming notification emails from Enote
# 				and upload the detected events in a cloud DB for later processing.
# Language:		Perl
# Author:		Marco Ruiz Mora
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

use strict;
use warnings;
use lib "/home/rumarco/usr/lib64/perl5";

use DBI;
use POSIX qw(strftime);

#Database connection statement
my $dbh = DBI->connect('dbi:mysql:dbname=gpsinternaldb;port=1531;host=g1t4741.austin.hp.com','gpsinternaldb','Welcome-1234',{AutoCommit=>0,RaiseError=>0,PrintError=>1});

#Init of variables
my $ENOTE_MAIL_BYTES_FILE = '/home/rumarco/enote_mail_bytes.tmp';
my $last_byte;
my $line;
my $alert_page;
my $serverDate = "";
my $sth;
my $dispatched_ticket_id_body;
my $dispatched_ticket_workgroup;
my $dispatched_ticket_id;
my $ticket_dispatched_prio;
my $update_statement;
my $rv;
my $ttr_ticket_id;
my $ttr_ticket_prio;
my $ttr_percent;
my $sms_ttr_subject;
my $full_ticket_subject;
my $complete_EON_WG;
my $is_EON_complete = 0;
my $EON_Subject;
my $EON_Id; 

#Checking if pointer for mail spool file exists and performing actions according to condition
if (-e $ENOTE_MAIL_BYTES_FILE)
{
        open(MY_ENOTE_FILE, $ENOTE_MAIL_BYTES_FILE)
                or die "Error while reading file $ENOTE_MAIL_BYTES_FILE: $!\n";
        while(<MY_ENOTE_FILE>)
        {
                chomp;
                $last_byte = $_;
        }
}
else
{
        open(my $fh, '>', $ENOTE_MAIL_BYTES_FILE)
                or die "Error while creating file $ENOTE_MAIL_BYTES_FILE: $!\n";
        print $fh "0\n";
        close $fh;
        $last_byte = 0;
}

#Declaring mail spool file to check for enote alerts and checking it since last line read
my $FILE = '/var/spool/mail/rumarco';
open (INFILE, $FILE) || die "Not able to open the file: $FILE \n";
for (;;)
{
	if ($last_byte == 0)
    {
    	seek(INFILE, $last_byte, 0);
    }
    else
    {
    	seek(INFILE, $last_byte, 1);
    }

    for (; $_ = <INFILE>; $last_byte = tell)
    {
    	my $line = $_;
        chomp($line);
        
        #Condition that searches for SLO emails and make insert of ticket into into db speficied for it
        if ($line =~ m/^Subject:\s([\w|\-|\s|\d]+\s:\s(N-IM[\d|-]+)\s(\(.+\))\s-\s(TTR\s[\w|\d|-|\s]+))/)
       	{
        	$serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
        	$ttr_ticket_id = $2;
        	$ttr_ticket_prio = $3;
        	$ttr_percent = $4;
        	$sms_ttr_subject = "ALERT: Incident $ttr_ticket_id $ttr_ticket_prio with $ttr_percent";
        	$sth = $dbh->prepare("SELECT ticket_workgroup FROM ticket_in_dispatched
        							WHERE ticket_id = ?");
			$sth->execute($ttr_ticket_id) or die $DBI::errstr;
			while (my @results = $sth->fetchrow()) 
			{
				my $ticket_ttr_workgroup = $results[0];
				$sth = $dbh->prepare("INSERT INTO ticket_with_slo
                       (ticket_id, ticket_subject, ticket_workgroup, ticket_sent_pager, ticket_date_added_db, sms_message_to_mobile, ticket_date_sent_page)
                        values
                       (?, ?, ?, ?, ?, ?,?)");
				$sth->execute($ttr_ticket_id, $1, $ticket_ttr_workgroup, 'N', $serverDate, $sms_ttr_subject,'null') or die $DBI::errstr;
				$sth->finish();
				$dbh->commit or die $DBI::errstr;				
			}        	        	
        }
        #Condition that searches for dispatched emails and gets priority and ticket it
        if ($line =~ m/^Subject:\s([\w|\-|\s|\d]+\s:\s(N-IM[\d|-]+)\s(\(.+\))\s-\sDispatched)/)
        {
			$serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
			$dispatched_ticket_id = $2;
			$ticket_dispatched_prio = $3;
			$full_ticket_subject = $1;
        }
        #Condition that searches for workgroup in dispatched email body and compares it with $dispatched_ticket_id
        if ($line =~ m/(^N-IM[\d|-]+)\shas been\sdispatched\sto\sassignment\sgroup\s?([\w\d|-]+)/)
        {
			$dispatched_ticket_id_body = $1;
			$dispatched_ticket_workgroup = $2;
			if ($dispatched_ticket_id eq $dispatched_ticket_id_body)
			{
				my $sms_subject = "ALERT: Incident $dispatched_ticket_id $ticket_dispatched_prio assigned to $2\n";
				$sth = $dbh->prepare("INSERT INTO ticket_in_dispatched
            	          (ticket_id, ticket_subject, ticket_workgroup, ticket_sent_pager, ticket_date_added_db, sms_message_to_mobile,ticket_date_sent_page )
            	            values
                	       (?, ?, ?, ?, ?, ?,?)");
				$sth->execute($dispatched_ticket_id, $full_ticket_subject, $dispatched_ticket_workgroup, 'N', $serverDate, $sms_subject,'null') or die $DBI::errstr;
				$sth->finish();
				$dbh->commit or die $DBI::errstr;
			}			
        }
        #Condition for EON Notifications
    	$is_EON_complete = 0;
    	if (/^Subject:\s(EON[\s|\w\d|-]+[\w\d]+\sEscalation\sAlert)\s-\s([\d]+)/ .. /View more details/)
    	{
   
        	if (/^Event & Esc Level.*/ .. /@[\d]+:[\d]+/)
        	{
            	if (/^Event & Esc Level:\s*(\d+)/)
            	{
            		$EON_Id = $1;
            	}
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
    				$serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
    				$complete_EON_WG =~ s/=|Message:|Tkt:|\s\s//g;
    				$complete_EON_WG =~ m/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)/;
    				my $EON_problem  = $6;
    				my $EON_team = $7;
    				$EON_problem =~ s/Prob://gi;
    				$EON_team =~ s/Esc.Team://gi;
    				my $complete_EON_to_DB = "EON Escalation $EON_Id: $EON_problem\n";
        				
    				$sth = $dbh->prepare("INSERT INTO ticket_in_dispatched
            	          (ticket_id, ticket_subject, ticket_workgroup, ticket_sent_pager, ticket_date_added_db, sms_message_to_mobile,ticket_date_sent_page )
            	            values
                	       (?, ?, ?, ?, ?, ?,?)");
					$sth->execute($EON_Id, $complete_EON_to_DB, $EON_team, 'N', $serverDate, $complete_EON_to_DB,'null') or die $DBI::errstr;
					$sth->finish();
					$dbh->commit or die $DBI::errstr;
   				}
        	}
    	}
    
                
        ##### FOR DTV PAGING #####
        if (/From\snoreply@[\w\d|.]+\s+[\w\d|\s|:]+[\d]+$/ .. /Status: O/)
        {
        	if ($line =~ m/Subject:\s([\w\d|:|\s|+|?.]+)/)
        	{
        		$serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
        		$sth = $dbh->prepare("INSERT INTO dtv_attention_pages
                       (att_sms_alert_subject, att_sent_sms, att_alert_added_db)
                        values
                       (?, ?, ?)");
				$sth->execute($1, 'N', $serverDate) or die $DBI::errstr;
				$sth->finish();
				$dbh->commit or die $DBI::errstr;        		
        	}        	
        }
    }    
    last;
    $dbh->disconnect;
}

$last_byte = tell(INFILE);
open(my $fh, '>', $ENOTE_MAIL_BYTES_FILE)
        or die "Error while creating file $ENOTE_MAIL_BYTES_FILE: $!\n";
print $fh "$last_byte\n";
close $fh;
