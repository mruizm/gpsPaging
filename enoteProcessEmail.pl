#!/usr/bin/perl
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# File: 		enoteProcessingEmail.pl
# Description: 	Script that processes the incoming notification emails from Enote
# 				and upload the detected events in a cloud DB for later processing.
# Language:		Perl
# 
#
#
#
#
use strict;
use warnings;
use lib "/home/rumarco/usr/lib64/perl5";

use DBI;
use POSIX qw(strftime);

my $dbh = DBI->connect('dbi:mysql:dbname=gpsinternaldb;port=1531;host=g1t4741.austin.hp.com','gpsinternaldb','Welcome-1234',{AutoCommit=>0,RaiseError=>0,PrintError=>1});

my $ENOTE_MAIL_BYTES_FILE = '/home/rumarco/enote_mail_bytes.tmp';
my $last_byte;
my $line;
my $alert_page;
my $serverDate = "";
my $sth;
my $dispatched_ticket_id_body;
my $dispatched_ticket_workgroup;
my $dispatched_ticket_id;
my $update_statement;
my $rv;

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
        
        if ($line =~ m/^Subject:\s([\w|\-|\s|\d]+\s:\s(N-IM[\d|-]+)\s\(.+\)\s-\s(TTR\s[\w|\d|-|\s]+))/)
       	{
        	$serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
        	$sth = $dbh->prepare("INSERT INTO ticket_with_slo
                       (ticket_id, ticket_subject, ticket_workgroup, ticket_sent_pager, ticket_date_added_db, sms_message_to_mobile, ticket_date_sent_page)
                        values
                       (?, ?, ?, ?, ?, ?,?)");
			$sth->execute($2, $3, 'null', 'N', $serverDate, $1,'null') or die $DBI::errstr;
			$sth->finish();
			$dbh->commit or die $DBI::errstr;
        	#print "ALERT: $1 $2 $3\n";
        	#print "ALERT: $1\n";
        	
        }
        if ($line =~ m/^Subject:\s([\w|\-|\s|\d]+\s:\s(N-IM[\d|-]+)\s\(.+\)\s-\sDispatched)/)
        {
			$serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
			$dispatched_ticket_id = $1;
			$sth = $dbh->prepare("INSERT INTO ticket_in_dispatched
                       (ticket_id, ticket_subject, ticket_workgroup, ticket_sent_pager, ticket_date_added_db, sms_message_to_mobile,ticket_date_sent_page )
                        values
                       (?, ?, ?, ?, ?, ?,?)");
			$sth->execute($2, 'null', 'null', 'N', $serverDate, $1,'null') or die $DBI::errstr;
			$sth->finish();
			$dbh->commit or die $DBI::errstr;
			#print "ALERT: $2\n";
			#print "ALERT: $1 $2\n";
        }
        if ($line =~ m/(^N-IM[\d|-]+)\shas been\sdispatched\sto\sassignment\sgroup([\w\d|-]+)/)
        {
			$dispatched_ticket_id_body = $1;
			$dispatched_ticket_workgroup = $2;
			if ($dispatched_ticket_id == $dispatched_ticket_id_body)
			{
				$update_statement = "UPDATE ticket_in_dispatched SET ticket_workgroup = ? WHERE ticket_id = ?";
				$rv = $dbh->do($update_statement, undef, $dispatched_ticket_workgroup, $dispatched_ticket_id); 
				$DBI::err && die $DBI::errstr;
			}
        }        
        ##### FOR DTV PAGING #####
        #if ($line =~ m/From\snoreply@[\w\d|.]+\s+[\w\d|\s|:]+[\d]+$/)
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
}
$dbh->disconnect;
$last_byte = tell(INFILE);
open(my $fh, '>', $ENOTE_MAIL_BYTES_FILE)
        or die "Error while creating file $ENOTE_MAIL_BYTES_FILE: $!\n";
print $fh "$last_byte\n";
close $fh;
