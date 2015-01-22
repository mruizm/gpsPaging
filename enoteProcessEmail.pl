#!/usr/bin/perl
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# File:                 enoteProcessingEmail.pl
# Description:                  Script that processes the incoming notification emails from Enote
#                       and EON and then uploads the detected events in DB for later processing.
# Language:             Perl
# Author:               Marco Ruiz Mora
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

use strict;
use warnings;
use lib "/home/rumarco/usr/lib64/perl5";
use DBI;
use POSIX qw(strftime);

#Database connection statement
my $dbh = DBI->connect('dbi:mysql:dbname=itopagingdb;port=3306;host=c9t03823.itcs.hp.com','gpspaging','GPSroot2013',{AutoCommit=>0,RaiseError=>0,PrintError=>1});

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
my $ttr_full_desc;
my $ttr_ticket_id;
my $ttr_ticket_prio;
my $ttr_percent;
my $sms_ttr_subject;
my $full_ticket_subject;
my $complete_EON_WG;
my $is_EON_complete = 0;
my $EON_Subject;
my $EON_Id;
my $complete_EON_to_DB;
my $EON_Multi_Line;
my $complete_One_Line;
my $complete_One_Line_no_N;
my $if_ticket_exists_in_db = 0;

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
        if ($line =~ m/^Subject:\s([\w|\-|\s|\d]+\s:\s(N-IM[\d|-]+)\s(\(.+\))\s-\s(TT[R|O]\s[\w|\d|-|\s]+))/)
        {
            $serverDate = strftime("%m/%d/%Y %I:%M %p %z", localtime());
            $ttr_full_desc = $1;
            $ttr_ticket_id = $2;
            $ttr_ticket_prio = $3;
            $ttr_percent = $4;
            #$sms_ttr_subject = "ALERT: Incident $ttr_ticket_id $ttr_ticket_prio with $ttr_percent";
            $sms_ttr_subject = "ALERT: $ttr_full_desc";
            print "$sms_ttr_subject\n";
            $sth = $dbh->prepare("SELECT ticket_workgroup FROM ticket_in_dispatched
                                  WHERE ticket_id = ?");
            $sth->execute($ttr_ticket_id) or die $DBI::errstr;
            while (my @results = $sth->fetchrow())
            {
                my $ticket_ttr_workgroup = $results[0];
                $sth = $dbh->prepare("INSERT INTO ticket_with_slo
                                    (ticket_id, ticket_subject, ticket_workgroup, ticket_sent_pager, ticket_date_added_db, sms_message_to_mobile, ticket_date_sent_page, ticket_sms_escalation_1_sent, ticket_sms_escalation_2_sent)
                                    values
                                    (?, ?, ?, ?, ?, ?, ?, ?, ?)");
                $sth->execute($ttr_ticket_id, $1, $ticket_ttr_workgroup, 'N', $serverDate, $sms_ttr_subject,'null', 'N', 'N') or die $DBI::errstr;
                $sth->finish();
                $dbh->commit;
            }
        }
        #Condition that searches for dispatched emails and gets priority and ticket it
        if ($line =~ m/^Subject:\s([\w|\-|\s|\d]+\s:\s(N-IM[\d|-]+)\s(\(.+\))\s-\sDispatched)/)
        {
            $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
            $dispatched_ticket_id = $2;
            $ticket_dispatched_prio = $3;
            #$full_ticket_subject = $1;
            $full_ticket_subject = "$2 $3";
            #Check if ticket exists in db prior to add it to db
            $sth = $dbh->prepare("SELECT ticket_id FROM ticket_in_dispatched
                                  WHERE ticket_id = ?");
            $sth->execute($dispatched_ticket_id) or die $DBI::errstr;
            while (my @results = $sth->fetchrow())
            {
                $if_ticket_exists_in_db++;
            }

        }
        #Condition that searches for workgroup in dispatched email body and compares it with $dispatched_ticket_id
        if ($line =~ m/(^N-IM[\d|-]+)\shas been\sdispatched\sto\sassignment\sgroup\s?([\w\d|-]+)/)
        {
            $dispatched_ticket_id_body = $1;
            $dispatched_ticket_workgroup = $2;

            #Condition that if TRUE adds entry into dispatched tickets DB
            if (($dispatched_ticket_id eq $dispatched_ticket_id_body) && ($dispatched_ticket_workgroup ne "W-INCFLS-ESM-RBA") && ($if_ticket_exists_in_db == 0))
            {
                #my $sms_subject = "ALERT: Incident $dispatched_ticket_id $ticket_dispatched_prio assigned to $2\n";
                my $sms_subject = "ALERT: INCIDENT $full_ticket_subject";
                print "$sms_subject\n";
                $sth = $dbh->prepare("INSERT INTO ticket_in_dispatched
                                    (ticket_id, ticket_subject, ticket_workgroup, ticket_sent_pager, ticket_date_added_db, sms_message_to_mobile,ticket_date_sent_page )
                                    values
                                    (?, ?, ?, ?, ?, ?,?)");
                $sth->execute($dispatched_ticket_id, $full_ticket_subject, $dispatched_ticket_workgroup, 'N', $serverDate, $sms_subject,'null') or die $DBI::errstr;
                $sth->finish();
                $dbh->commit;
            }
            $if_ticket_exists_in_db = 0;
        }
        #Condition for EON Notifications
        $is_EON_complete = 0;
        if (/^Subject:\s(EON[\s|\w\d|-]+[\w\d]+\sEscalation\sAlert)\s-\s([\d]+)/ .. /View more details/)
        {
            if (/^Subject:\s(EON[\s|\w\d|-]+[\w\d]+\sEscalation\sAlert)\s-\s([\d]+)/)
            {
                $EON_Subject = $1;
                $EON_Id = $2;
            }
            if (/^Event & Esc Level.*/ .. /@[\d]+/)
            {
                my $EON_Wg_Line =  $_;
                if (/^Message:/ .. /@[\d]+/)
                {
                    chomp($EON_Wg_Line);
                    $complete_EON_WG = $complete_EON_WG.$EON_Wg_Line;
                }
                if ($complete_EON_WG =~ m/@[\d]+/)
                {
                    $complete_EON_WG = $complete_EON_WG."\n";
                    $is_EON_complete = 1;
                }
                if($is_EON_complete == 1)
                {
                    #print "$complete_EON_WG";
                    $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
                    $complete_EON_WG =~ s/=|Message:|Tkt:|\s\s//g;
                    $complete_EON_WG =~ m/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)/;
                    my $EON_problem  = $6;
                    my $EON_team = $7;
                    $EON_problem =~ s/Prob://gi;
                    $EON_team =~ s/Esc.Team://gi;
                    $complete_EON_to_DB = "EON Escalation $EON_Id: $EON_problem\n";
                    print "$complete_EON_to_DB";
                    $sth = $dbh->prepare("INSERT INTO eon_in_dispatched
                                        (eon_id, eon_subject, eon_workgroup, eon_sent_pager, eon_date_added_db, eon_sms_message_to_mobile, eon_date_sent_page )
                                        values
                                        (?, ?, ?, ?, ?, ?,?)");
                    $sth->execute($EON_Id, $complete_EON_to_DB, $EON_team, 'N', $serverDate, $complete_EON_to_DB,'null') or die $DBI::errstr;
                    $sth->finish();
                    $dbh->commit;
                    $complete_EON_WG = "";
                }
            }
        }
        #OTHER EON FORMAT
        $is_EON_complete = 0;
        if (/Subject:\sEON\sEvent\s(\d*)\sInitiated/ .. /This message was sent to you because this email address/)
        {
            if (/Subject:\sEON\sEvent\s(\d*)\sInitiated/)
            {
                $EON_Id = $1;
                #print "$EON_Id\n";
            }
            my $EON_Wg_Line =  $_;
            if (/^Message Text:/ .. /@[\d]+/)
            {
                chomp($EON_Wg_Line);
                $complete_EON_WG = $complete_EON_WG.$EON_Wg_Line;
            }
            if ($complete_EON_WG =~ m/@[\d]+/)
            {
                $complete_EON_WG = $complete_EON_WG."\n";
                $is_EON_complete = 1;
            }
            if($is_EON_complete == 1)
            {
                $complete_EON_WG =~ s/=|Message Text:|Tkt:|\s\s\s//g;
                #print "$complete_EON_WG";
                $complete_EON_WG =~ m/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)\/(.*)/;
                my $EON_problem  = $6;
                my $EON_team = $7;
                $EON_problem =~ s/Prob://gi;
                $EON_team =~ s/Esc.Team://gi;
                $complete_EON_to_DB = "EON Escalation $EON_Id: $EON_problem\n";
                #print "$complete_EON_to_DB";
                $sth = $dbh->prepare("INSERT INTO eon_in_dispatched
                                    (eon_id, eon_subject, eon_workgroup, eon_sent_pager, eon_date_added_db, eon_sms_message_to_mobile, eon_date_sent_page )
                                     values
                                    (?, ?, ?, ?, ?, ?,?)");
                                    $sth->execute($EON_Id, $complete_EON_to_DB, $EON_team, 'N', $serverDate, $complete_EON_to_DB,'null') or die $DBI::errstr;
                $sth->finish();
                $dbh->commit;
                $complete_EON_WG = "";
            }
        }
        ##### FOR DTV PAGING #####./
        if (/From\snoreply@[\w\d|.]+\s+[\w\d|\s|:]+[\d]+$/ .. /Attention Notification/)
        {
            if ($line =~ m/Subject:\s(.*)/)
            {
                $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
                $sth = $dbh->prepare("INSERT INTO dtv_attention_pages
                                    (att_sms_alert_subject, att_sent_sms, att_alert_added_db)
                                    values
                                    (?, ?, ?)");
                $sth->execute($1, 'N', $serverDate) or die $DBI::errstr;
                $sth->finish();
                $dbh->commit;
                print "$1\n";
            }
        }
    }
    $dbh->disconnect;
    last;
}
$last_byte = tell(INFILE);
open(my $fh, '>', $ENOTE_MAIL_BYTES_FILE)
    or die "Error while creating file $ENOTE_MAIL_BYTES_FILE: $!\n";
print $fh "$last_byte\n";
close $fh;
