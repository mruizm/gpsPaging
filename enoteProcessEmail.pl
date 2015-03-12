#!/usr/bin/perl
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# File:                 enoteProcessingEmail.pl
# Description:          Script that processes the incoming notification emails from Enote
#                       and EON and then uploads the detected events in DB for later processing.
# Language:             Perl
# Author:               Marco Ruiz Mora
# Version 3.0
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

use strict;
use warnings;
##use lib "/opt/mount1/itopaging/usr/lib64/perl5";
use DBI;
use POSIX qw(strftime);
use DateTime;

#Database connection statement
our $dbh = DBI->connect('dbi:mysql:dbname=itopagingdb_staging;port=3306;host=c9t03823.itcs.hp.com','gpspaging','GPSroot2013',{AutoCommit=>0,RaiseError=>0,PrintError=>1});

#Init of variables
my $ENOTE_MAIL_BYTES_FILE = '/opt/mount1/itopaging/enote_mail_bytes_staging.tmp';
my $loggerDBfile = "/opt/mount1/itopaging/pagingDBerror_staging.log";
my ($last_byte, $line, $serverDate, $alert_page);
my ($sth, $sth_insert, $attn_dtv_msj);
my ($dispatched_ticket_id_body, $ticket_customer, $full_ticket_subject, $dispatched_ticket_workgroup, $dispatched_ticket_id, $ticket_dispatched_prio, $sms_subject, $sms_ticket_subject);
my ($ttr_full_desc, $ttr_ticket_id, $ttr_customer, $ttr_ticket_prio, $ttr_percent, $sms_ttr_subject, $ttr_percent_raw);
my $is_EON_complete = "0";
my $if_ticket_exists_in_db = "0";
my ($EON_Id, $EON_Subject, $complete_EON_WG, $complete_EON_to_DB, $EON_Multi_Line);
my ($EON_Ref, $EON_Sev, $EON_Imp, $EON_Client, $EON_Sys, $EON_problem, $EON_team, $EON_Start);
my @results;

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
        #Condition that searches for dispatched emails and gets priority and ticket it
        if ($line =~ m/^Subject:\s(([\w|\-|\s|\d]+\s):\s(N-IM[\d|-]+)\s(\(.+\))\s-\sDispatched)/)
        {
            ##$serverDate = strftime("%m/%d/%Y %I:%M:%S %p %z", localtime());
            $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
            $full_ticket_subject = $1;
            $ticket_customer = $2;
            $dispatched_ticket_id = $3;
            $ticket_dispatched_prio = $4;
            
            chomp($full_ticket_subject);
            $full_ticket_subject =~ s/\s+$//g; 
                       
            chomp($ticket_customer);
            $ticket_customer =~ s/\s+$//g;   
             
            chomp($dispatched_ticket_id);
            $dispatched_ticket_id =~ s/\s+$//g;             
            
            chomp($ticket_dispatched_prio);
            $ticket_dispatched_prio =~ s/[\(|\)]//g;
            $ticket_dispatched_prio =~ s/\s+$//g;  
         
            #Check if ticket exists in db prior to add it to db
            $sth = $dbh->prepare("SELECT ticket_id FROM ticket_in_dispatched
                                  WHERE ticket_id = ?");
            $sth->execute($dispatched_ticket_id) 
            	or database_logger($serverDate, $loggerDBfile, $DBI::errstr);
            @results = ();
            while (@results = $sth->fetchrow())
            {
                $if_ticket_exists_in_db++;
            }
        }
        #Condition that searches for workgroup in dispatched email body and compares it with $dispatched_ticket_id
        my $count_line = 0;
        my $complete_line_workg = "";
        if ($line =~ m/(^N-IM[\d|-]+)\shas been\sdispatched\sto\sassignment\sgroup\s?([\w\d|-]+)/){
            $dispatched_ticket_id_body = $1;
            $dispatched_ticket_workgroup = $2;
            
            chomp($dispatched_ticket_id_body);
            $dispatched_ticket_id_body =~ s/\s+$//g;
            
            chomp($dispatched_ticket_workgroup);
            $dispatched_ticket_workgroup =~ s/[\(|\)]//g;
            $dispatched_ticket_workgroup =~ s/\s+$//g;
           
            
            $sms_subject = "ALERT: $ticket_dispatched_prio - $dispatched_ticket_id";
            chomp($sms_subject);
            print "$sms_subject - $dispatched_ticket_workgroup\n";

            #Condition that if TRUE adds entry into dispatched tickets DB
            if (($dispatched_ticket_id eq $dispatched_ticket_id_body) && ($dispatched_ticket_workgroup ne "W-INCFLS-ESM-RBA") && ($if_ticket_exists_in_db eq "0"))
            {
                $sth = $dbh->prepare("INSERT INTO ticket_in_dispatched
                                    (ticket_id, ticket_subject, ticket_customer, ticket_priority, ticket_workgroup, ticket_date_added_db, sms_message_to_mobile, ticket_processed, ticket_date_processed)
                                    values
                                    (?, ?, ?, ?, ?, ?, ?, ?, ?)");
                $sth->execute($dispatched_ticket_id, $full_ticket_subject, $ticket_customer, $ticket_dispatched_prio, $dispatched_ticket_workgroup, $serverDate,  $sms_subject, '0', 'null') 
            	   	or database_logger($serverDate, $loggerDBfile, $DBI::errstr);
                $sth->finish();
                $dbh->commit;
            }
            $if_ticket_exists_in_db = 0;
        	
        }
        #Condition that searches for SLO emails and make insert of ticket into into db speficied for it
        if ($line =~ m/^Subject:\s(([\w|\-|\s|\d]+\s):\s(N-IM[\d|-]+)\s(\(.+\))\s-\s(TT[R|O]\s[\w|\d|-|\s]+))/)
        {
            $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
            $ttr_full_desc = $1;
            $ttr_customer = $2;
            $ttr_ticket_id = $3;
            $ttr_ticket_prio = $4;
            $ttr_percent = $5;
            
            chomp($ttr_full_desc);
                        
            $ttr_customer =~ s/\s+$//g;  
            chomp($ttr_customer);
            
            chomp($ttr_ticket_id);
            
            chomp($ttr_ticket_prio);
            
            $ttr_percent_raw = $ttr_percent;
            chomp ($ttr_percent_raw);
            if ($ttr_percent =~ m/[TTO|TTR] 50 Percent/){
            	$ttr_percent = 50;
            }
            if ($ttr_percent =~ m/[TTO|TTR] 75 Percent/){
            	$ttr_percent = 75;
            }
            if ($ttr_percent =~ m/[TTO|TTR] deadline/){
            	$ttr_percent = 100;
            }
            chomp($ttr_percent);
            $ttr_ticket_prio =~ s/[\(|\)]//g;
            chomp($ttr_ticket_prio);
            $sms_ttr_subject = "ALERT: $ttr_ticket_prio - $ttr_percent_raw - $ttr_ticket_id";
            chomp($sms_ttr_subject);
            print "$sms_ttr_subject\n";
            $sth = $dbh->prepare("SELECT ticket_workgroup FROM ticket_in_dispatched
                                  WHERE ticket_id = ?");
            $sth->execute($ttr_ticket_id) 
            	or database_logger($serverDate, $DBI::errstr, $ttr_ticket_id);
            while (@results = $sth->fetchrow())
            {
                my $ticket_ttr_workgroup = $results[0];
                $sth_insert = $dbh->prepare("INSERT INTO ticket_with_slo
                                    (ticket_id, ticket_subject, ticket_customer, ticket_priority, ticket_slo_percent, ticket_workgroup, ticket_date_added_db, sms_message_to_mobile, ticket_processed, ticket_date_processed)
                                    values
                                   (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
                $sth_insert->execute($ttr_ticket_id, $ttr_full_desc, $ttr_customer, $ttr_ticket_prio, $ttr_percent, $ticket_ttr_workgroup, $serverDate, $sms_ttr_subject, '0', 'null') 
                	or database_logger($serverDate, $loggerDBfile, $DBI::errstr);
                $sth_insert->finish();
                $dbh->commit;
            }
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
                    $complete_EON_WG =~ s/=|Message:|Tkt:|\s\s//g;
                    $complete_EON_WG =~ m/(.*)\/(Sev.*)\/(Impact:.*)\/(Client:.*)\/(Sys:.*)\/(Prob:.*)\/(Esc.Team.*)\/(Start.*)/;
                	$serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
                	$EON_Ref = $1;
               		$EON_Sev = $2;
               	 	$EON_Imp = $3;
                	$EON_Client = $4;
                	$EON_Sys = $5;
                	$EON_problem  = $6;
                	$EON_team = $7;
                	$EON_Start = $8;
                	$EON_Imp =~ s/Impact://gi;
                	$EON_Client =~ s/Client://gi;
                	$EON_Sys =~ s/Sys://gi;
                	$EON_problem =~ s/Prob://gi;
                	$EON_team =~ s/Esc.Team://gi;
                	$EON_Start =~ s/Start@//gi;
                    $complete_EON_to_DB = "EON Escalation $EON_Id: $EON_problem\n";
                    print "$complete_EON_to_DB";
                    $sth = $dbh->prepare("INSERT INTO eon_in_dispatched
                                        (eon_id, eon_reference, eon_severity, eon_impact, eon_client, eon_system, eon_problem, eon_workgroup, eon_start, eon_date_added_db, eon_sms_message_to_mobile, eon_processed, eon_date_processed)
                                        values
                                        (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
                    $sth->execute($EON_Id, $EON_Ref, $EON_Sev, $EON_Imp, $EON_Client, $EON_Sys, $EON_problem, $EON_team, $EON_Start, $serverDate, $complete_EON_to_DB,'0', 'null') 
                    	or database_logger($serverDate, $loggerDBfile, $DBI::errstr);
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
                $complete_EON_WG =~ m/(.*)\/(Sev.*)\/(Impact:.*)\/(Client:.*)\/(Sys:.*)\/(Prob:.*)\/(Esc.Team.*)\/(Start.*)/;
                $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
                my $EON_Ref = $1;
                my $EON_Sev = $2;
                my $EON_Imp = $3;
                my $EON_Client = $4;
                my $EON_Sys = $5;
                my $EON_problem  = $6;
                my $EON_team = $7;
                my $EON_Start = $8;
                $EON_Imp =~ s/Impact://gi;
                $EON_Client =~ s/Client://gi;
                $EON_Sys =~ s/Sys://gi;
                $EON_problem =~ s/Prob://gi;
                $EON_team =~ s/Esc.Team://gi;
                $EON_Start =~ s/Start@//gi;
                $complete_EON_to_DB = "EON Escalation $EON_Id: $EON_problem\n";
                print "$complete_EON_to_DB";
                $sth = $dbh->prepare("INSERT INTO eon_in_dispatched
                                        (eon_id, eon_reference, eon_severity, eon_impact, eon_client, eon_system, eon_problem, eon_workgroup, eon_start, eon_date_added_db, eon_sms_message_to_mobile, eon_processed, eon_date_processed )
                                        values
                                        (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
                    $sth->execute($EON_Id, $EON_Ref, $EON_Sev, $EON_Imp, $EON_Client, $EON_Sys, $EON_problem, $EON_team, $EON_Start, $serverDate, $complete_EON_to_DB, '0', 'null') 
                    	or database_logger($serverDate, $loggerDBfile, $DBI::errstr);
                    	##or die $DBI::errstr;
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
                $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
                $attn_dtv_msj = "ALERT: $1";

                $sth = $dbh->prepare("INSERT INTO dtv_attn_pages
                                    (attn_subject, attn_customer, attn_priority, attn_workgroup, attn_date_added_db, sms_message_to_mobile, attn_processed, attn_date_processed)
                                    values
                                    (?, ?, ?, ?, ?, ?, ?, ?)");
                $sth->execute($1, 'DTV', 'Priority 1', 'DTV-PAGES', $serverDate, $attn_dtv_msj, '0', 'null') 
                	or database_logger($serverDate, $loggerDBfile, $DBI::errstr);
                $sth->finish();
                $dbh->commit;
                print "$attn_dtv_msj\n";
            }
        }
    }
    last;
}
$last_byte = tell(INFILE);
open(my $fh, '>', $ENOTE_MAIL_BYTES_FILE)
    or die "Error while creating file $ENOTE_MAIL_BYTES_FILE: $!\n";
print $fh "$last_byte\n";
close $fh;

##
## Exec of sub that process unflagged entries for SMS processing
##
processEntriesToNotificationTable();
$dbh->disconnect();

## Sub that process the entries which has 'ticket_processed' in '0' (for dispatched and SLO)
## in order to add them to ito_sms_to_deliver table. 
## Each generated entry is for a sms message that should be processed by another funcion to 
## send the actual sms to mobile(s)
## @Parms: None
## Return: None
sub processEntriesToNotificationTable{	
	#Get those entries which has 'ticket_processed' flag to '0'
	my $processEntriesLogfile = "/opt/mount1/itopaging/processingSmserror_staging.log";
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	my @userNames = ();
	my $userNameCustomerCodeStatus;
	my $userEon;
	my $userPriorityStatus = 0;
	my $customerAllFlag = 0;
	
	my ($ticketId, $ticketCustomer, $ticketPriority, $ticketWorkGroup, $smsMessage, $ticketPriorityFormat, $dateAddedDb, $entryId, $sloPercent);
	
	# Processing for dispatched alerts
	my $getUnProcessedDispEntries = 
					"(SELECT ticket_id, ticket_customer, ticket_priority, ticket_workgroup, sms_message_to_mobile, ticket_date_added_db, ticket_entry_id, ticket_slo_percent 
						FROM ticket_in_dispatched where ticket_processed = '0') 
					UNION
					(SELECT ticket_id, ticket_customer, ticket_priority, ticket_workgroup, sms_message_to_mobile, ticket_date_added_db, ticket_entry_id, ticket_slo_percent 
						FROM ticket_with_slo where ticket_processed = '0')
					UNION
					(SELECT eon_id, eon_customer, eon_priority, eon_workgroup, eon_sms_message_to_mobile, eon_date_added_db, eon_entry_id, eon_slo_percent 
						FROM eon_in_dispatched where eon_processed = '0')			
					UNION
					(SELECT attn_id, attn_customer, attn_priority, attn_workgroup, sms_message_to_mobile, attn_date_added_db, attn_notif_id, attn_slo_percent 
						FROM dtv_attn_pages where attn_processed = '0')";
    
    my $sth_entries_to_process = $dbh->prepare($getUnProcessedDispEntries);
    $sth_entries_to_process->execute()
    	or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
    my $rows = $sth_entries_to_process->rows;
    database_logger($serverDate, $processEntriesLogfile, "===== Starting itopaging script... =====");
    database_logger($serverDate, $processEntriesLogfile, "Checking if new events in DB for processing...");
    if ($rows eq "0")
    {
    	print "No ticket entries found for processing!\n";
    	database_logger($serverDate, $processEntriesLogfile, "No entries found in DB for processing!");
    }
    else
    {
    	database_logger($serverDate, $processEntriesLogfile, "Event(s) Found in DB! Starting processing...");
    	#Process entries which has 'ticket_processed' flag to '0'
    	while (my @results = $sth_entries_to_process->fetchrow())
    	{
        	$ticketId			= $results[0];
        	$ticketCustomer 	= $results[1];
        	$ticketPriority 	= $results[2];
        	$ticketWorkGroup 	= $results[3];
        	$smsMessage			= $results[4];
        	$dateAddedDb		= $results[5];
        	$entryId			= $results[6];
        	$sloPercent			= $results[7];
        	
        	chomp($ticketCustomer);
        	print "========== Processing ticket $ticketId - Customer $ticketCustomer - Entry ID $entryId ==========\n";
        	chomp($ticketPriority);
        	chomp($ticketWorkGroup);
        	chomp($smsMessage);
        	chomp($sloPercent);
        	$ticketPriority =~ m/(Priority)\s(\d)/;
        	$ticketPriorityFormat = $2;
        	chomp($ticketPriorityFormat);
        	
        	#Gets all usernames suscribed to workgroup using team_name attribute
        	@userNames = queryGetUsernamesUsingworkgroup($dbh, $ticketWorkGroup);
        	if (! @userNames)
        	{
        		print "No usernames found for ticket $ticketId workgroup $ticketWorkGroup!\n";
        		database_logger($serverDate, $processEntriesLogfile, "No usernames found for ticket $ticketId workgroup $ticketWorkGroup!");
        	}
        	else{
        		#Loop around usernames obtained in sub queryGetUsernamesUsingworkgroup
        		foreach my $instanceUserName (@userNames){
        			$userNameCustomerCodeStatus = "";
        			#For each username check if customer is suscribed to process event for ticket's customer
        			print "\nChecking if username $instanceUserName has customer $ticketCustomer assigned...\n";
        			$userNameCustomerCodeStatus = queryGetCustomersUserName($dbh, $instanceUserName, $ticketCustomer, $ticketWorkGroup);
        			#When no usernames were found
        			if ($userNameCustomerCodeStatus)
        			{
        				print "Customer obtained for $instanceUserName is: $userNameCustomerCodeStatus\n";
        				if ( ($userNameCustomerCodeStatus ne $ticketCustomer) && ($userNameCustomerCodeStatus ne "ALL") )
        				{
        					print "No customer(s) found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup customer $ticketCustomer!\n";
        					database_logger($serverDate, $processEntriesLogfile, "No customer(s) found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!");
        				}        			
						if ($userNameCustomerCodeStatus eq $ticketCustomer){
							if ($ticketCustomer eq "EON")
							{
								print "Checking if username $instanceUserName has EON notification active...\n";
        						$userEon = queryUserNameEonSubscription($dbh,$instanceUserName);
        						chomp($userEon);        					
        						if ($userEon eq "1"){
        							print "EON notifications ENABLED!\n";
        							#Check if username is enrolled for ticket's priority for dispactched entries
        							$userPriorityStatus = queryUserNamePrioritySubscription($dbh, $instanceUserName, $ticketPriorityFormat, "0");
        							#If username is suscribed to priority add entre to ito_sms_to_deliver
        							if ($userPriorityStatus eq "1"){
        								print "Username $instanceUserName has $ticketPriority ticket subscribed!\n";
        								print "Generating entry in table ito_sms_to_deliver...\n";
        								print "Ticket $ticketId - $ticketPriority - $instanceUserName - $smsMessage\n";
        								insertEntrySmsDelivery($dbh, $instanceUserName, $smsMessage);
        							}
        							if (!$userPriorityStatus){
        								print "No Priority $ticketPriority subscription found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!\n";
        								database_logger($serverDate, $processEntriesLogfile, "No Priority $ticketPriorityFormat found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!");
        							}
        						}
							}
							if ($ticketCustomer ne "EON"){
								chomp($userNameCustomerCodeStatus);
								print "Customer $ticketCustomer found for username $instanceUserName!\n";
        						#Check if username is enrolled for ticket's priority for dispactched entries
        						print "Checking priority subscription for username $instanceUserName...\n";
        						$userPriorityStatus= queryUserNamePrioritySubscription($dbh, $instanceUserName, $ticketPriorityFormat, $sloPercent);
        						chomp($userPriorityStatus);
        						#If username is suscribed to priority add entre to ito_sms_to_deliver
        						if ( $userPriorityStatus eq "1"){
        							print "Username $instanceUserName has $ticketPriority ticket subscribed!\n";
        							print "Generating entry in table ito_sms_to_deliver...\n";
        							print "Ticket $ticketId - $ticketPriority - $instanceUserName - $smsMessage\n";
        							insertEntrySmsDelivery($dbh, $instanceUserName, $smsMessage);       				
        						} 
        						if (!$userPriorityStatus){
        						print "No Priority $ticketPriority subscription found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!\n";
        						database_logger($serverDate, $processEntriesLogfile, "No Priority $ticketPriorityFormat found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!");
        						}
							}
							##print "$userNameCustomerCodeStatus eq $ticketCustomer\n";

        				}
        				#When username has 'ALL' flag set (All customers notifications active)	
        				if ( ($userNameCustomerCodeStatus eq "ALL") && ($ticketCustomer eq "EON") ){
        					##print "ALL CONDITION\n";
        					chomp($userNameCustomerCodeStatus);
        					print "ALL flag found for username $instanceUserName!\n";
        					#Check if usename is enrolled in EON
        					print "Checking if username $instanceUserName has EON notification active...\n";
        					$userEon = queryUserNameEonSubscription($dbh, $instanceUserName);
        					chomp($userEon);        					
        					if ($userEon eq "1")
        					{
        						print "EON notifications ENABLED!\n";
        						#Check if username is enrolled for ticket's priority for dispactched entries
        						$userPriorityStatus = queryUserNamePrioritySubscription($dbh, $instanceUserName, $ticketPriorityFormat, "0");
        						#If username is suscribed to priority add entre to ito_sms_to_deliver
        						if ($userPriorityStatus eq "1"){
        							print "Username $instanceUserName has $ticketPriority ticket subscribed!\n";
        							print "Generating entry in table ito_sms_to_deliver...\n";
        							print "Ticket $ticketId - $ticketPriority - $instanceUserName - $smsMessage\n";
        							insertEntrySmsDelivery($dbh, $instanceUserName, $smsMessage);
        						}
        						if (!$userPriorityStatus){
        							print "No Priority $ticketPriority subscription found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!\n";
        							database_logger($serverDate, $processEntriesLogfile, "No Priority $ticketPriorityFormat found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!");
        						}	
        					}
        					if ($userEon ne "1"){
        						print "EON notifications DISABLED!\n";        						
        					}
        				}
        				if ( ($userNameCustomerCodeStatus eq "ALL") && ($ticketCustomer ne "EON") )
        				{
        					#Check if username is enrolled for ticket's priority for dispactched entries
        					$userPriorityStatus = queryUserNamePrioritySubscription($dbh, $instanceUserName, $ticketPriorityFormat, "0");
        					#If username is suscribed to priority add entre to ito_sms_to_deliver
        					if ($userPriorityStatus eq "1"){
        						print "Username $instanceUserName has $ticketPriority ticket subscribed!\n";
        						print "Generating entry in table ito_sms_to_deliver...\n";
        						print "Ticket $ticketId - $ticketPriority - $instanceUserName - $smsMessage\n";
        						insertEntrySmsDelivery($dbh, $instanceUserName, $smsMessage);
        					}
        					if (!$userPriorityStatus){
        						print "No Priority $ticketPriority subscription found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!\n";
        						database_logger($serverDate, $processEntriesLogfile, "No Priority $ticketPriorityFormat found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!");
        					}	
        				}
        			}
        			else{
            			print "No customer(s) entry found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup customer $ticketCustomer!\n";
        				database_logger($serverDate, $processEntriesLogfile, "No customer(s) found for username $instanceUserName ticket $ticketId workgroup $ticketWorkGroup!");
        			}        			      			
       			}        	
    		}
    		print "\nENTRY ID $entryId FLAGGED AS PROCESSED!\n\n";
    		#Condition to flag ticket entry as processed for dispatched
    		if ( ($sloPercent eq "0") && ($ticketCustomer ne "DTV") ){
    			my $ticket_processed_update = "UPDATE ticket_in_dispatched SET ticket_processed = \'1\', ticket_date_processed = \'$serverDate\' 
    											WHERE ticket_id = \'$ticketId\' AND ticket_date_added_db = \'$dateAddedDb\'";
    		
    			my $sth_ticketProcessed = $dbh->prepare($ticket_processed_update);
    			$sth_ticketProcessed->execute();   				
           		$sth_ticketProcessed->finish()
            		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
            	$dbh->commit;
    		}
    		#Condition to flag ticket entry as processed for DTV Pages
    		if ( ($sloPercent eq "0") && ($ticketCustomer eq "DTV") ){
    			my $ticket_processed_update = "UPDATE dtv_attn_pages SET attn_processed = \'1\', attn_date_processed = \'$serverDate\' 
    											WHERE attn_id = \'$ticketId\' AND attn_date_added_db = \'$dateAddedDb\'";
    		
    			my $sth_ticketProcessed = $dbh->prepare($ticket_processed_update);
    			$sth_ticketProcessed->execute();   				
           		$sth_ticketProcessed->finish()
            		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
            	$dbh->commit;
    		}
    		#Condition to flag ticket entry as processed for EON Notifications
    		if ( ($sloPercent eq "0") && ($ticketCustomer eq "EON") ){
    			my $ticket_processed_update = "UPDATE eon_in_dispatched SET eon_processed = \'1\', eon_date_processed = \'$serverDate\' 
    											WHERE eon_entry_id = \'$entryId\' AND eon_date_added_db = \'$dateAddedDb\'";
    		
    			my $sth_ticketProcessed = $dbh->prepare($ticket_processed_update);
    			$sth_ticketProcessed->execute();   				
           		$sth_ticketProcessed->finish()
            		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
            	$dbh->commit;
    		}
    		#Condition to flag ticket entry as processed for SLO
    		if ($sloPercent ne "0"){
    			my $ticket_processed_update = "UPDATE ticket_with_slo SET ticket_processed = \'1\', ticket_date_processed = \'$serverDate\' 
    											WHERE ticket_id = \'$ticketId\' AND ticket_date_added_db = \'$dateAddedDb\'";
    		
    			my $sth_ticketProcessed = $dbh->prepare($ticket_processed_update);
    			$sth_ticketProcessed->execute();   				
           		$sth_ticketProcessed->finish()
            		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
            	$dbh->commit;
    		}

   		}
    }
    database_logger($serverDate, $processEntriesLogfile, "Finished itopaging script!");        		
}

## Sub to obtain the usernames associated to ticket's workgroup 
## @Parms:
##		[0]: db connection
##		[1]: ticket workgroup
## Return: 
##		@userNamesArray: Array with usernames
sub queryGetUsernamesUsingworkgroup{
	my $dbh_priv = $_[0];
	my $ticketWorkGroupPriv = $_[1];
	my @userNamesArray = ();
	my $userName;
	my $processEntriesLogfile = "/opt/mount1/itopaging/pagingDBerror_staging.log";
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
			
	my $getUserNameUsingWorkGroup = "SELECT DISTINCT username FROM team_name_to_users 
										WHERE team_name IN (SELECT team_name from ticket_workgroup_to_team_name WHERE
										ticket_workgroup = \'$ticketWorkGroupPriv\')";
												
	my $sth_userNames_entry = $dbh_priv->prepare($getUserNameUsingWorkGroup);
	$sth_userNames_entry->execute()
		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
   	#Results based on query to obtain usernames
   	while (my @results = $sth_userNames_entry->fetchrow()) {
   		$userName = $results[0];
   		#Add usernames to array
   		push(@userNamesArray, $userName)
   	}
	return @userNamesArray;
}

## Sub to obtain the customers asociated to a username
## @Parms:
##		[0]: db connection
##		[1]: username
##		[2]: customer from ticket
##		[3]: ticket workgroup
## Returns:
##		Customer codes for entered username if available
sub queryGetCustomersUserName{
	my $dbh_priv = $_[0];
	my $userNamePriv = $_[1];
	my $customerCodePriv = $_[2];
	my $ticketWorkGroupPriv = $_[3];
	my $processEntriesLogfile = "/opt/mount1/itopaging/pagingDBerror_staging.log";
	my @customerArray = ();
	my $customerCode;
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	
	my $getCustomerCodeUsername = "SELECT customer_code FROM team_name_to_users 
        							WHERE username = \'$userNamePriv\' AND customer_code REGEXP \'$customerCodePriv|ALL\' 
        							AND team_name IN (SELECT team_name from ticket_workgroup_to_team_name 
        							WHERE ticket_workgroup = \'$ticketWorkGroupPriv\') ORDER BY customer_code ASC"; 
        												
   	my $sth_customerCodes = $dbh->prepare($getCustomerCodeUsername);
   	$sth_customerCodes->execute()
   		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
	#Results based on query to get customer code
	while (my @results = $sth_customerCodes->fetchrow()) {
		$customerCode = $results[0];
		if ($customerCode eq "ALL"){
			last;
		}
	}
	return $customerCode;	
}

## Sub to obtain the if username is active for ticket's priority
## @Parms:
##		[0]: db connection
##		[1]: username
##		[2]: priority ticket code
##		[3]: priority ticket percentage
## Returns:
##		0:	if not active
##		1: 	if active
sub queryUserNamePrioritySubscription{
	my $dbh_priv = $_[0];
	my $userNamePriv = $_[1];
	my $priorityTicketCode = $_[2];
	my $priorityTicketPercent = $_[3];
	my @userNameSubscriptionPriv = ();
	my $subsStatus = 0;
	my $usernamePrioStatus;
	my $processEntriesLogfile = "/opt/mount1/itopaging/pagingDBerror_staging.log";
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	
	my $priorityColumnConcat = "P".$priorityTicketCode."_is_".$priorityTicketPercent."_percent";
	
	my $getUsernamePrioStatus = "SELECT $priorityColumnConcat FROM users_to_notification_array 
        								WHERE username = \'$userNamePriv\'"; 
        												
   	my $sth_usernamePrioStatus = $dbh->prepare($getUsernamePrioStatus);
   	$sth_usernamePrioStatus->execute()
   		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
	#Results based on query to get username priority profile
	while (my @results = $sth_usernamePrioStatus->fetchrow()) {
		$usernamePrioStatus = $results[0];
	}
	return $usernamePrioStatus;	
}

## Sub to insert entry for sms delivery script
## @Parms:
##		[0]: db connection
##		[1]: username
##		[2]: sms text
##		
## Returns:
##		None
##		
sub insertEntrySmsDelivery{
	my $processEntriesLogfile = "/opt/mount1/itopaging/pagingDBerror_staging.log";
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	my $dbh_priv = $_[0];
	my $userNamePriv = $_[1];
	my $smsText = $_[2];
	
	my $insertSmsEntry = "INSERT INTO ito_sms_to_deliver
							(username, phone_number, sms_text, date_added_db)
							VALUES
							(\'$userNamePriv\', (SELECT user_mobile FROM users_info_table WHERE username = \'$userNamePriv\'), \'$smsText\', \'$serverDate\')";
							
	my $sth_insertSmsEntry = $dbh->prepare($insertSmsEntry);
	$sth_insertSmsEntry->execute()
		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
	$sth_insertSmsEntry->finish();
	$dbh_priv->commit;
}

## Sub to obtain the if username is active for EON
## @Parms:
##		[0]: db connection
##		[1]: username
## Returns:
##		0:	if not active
##		1: 	if active
sub queryUserNameEonSubscription{
	my $dbh_priv = $_[0];
	my $userNamePriv = $_[1];
	my $usernameInEon;
	my $processEntriesLogfile = "/opt/mount1/itopaging/pagingDBerror_staging.log";
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	
	my $getUsernameEonStatus = "SELECT eon_active FROM users_info_table
        								WHERE username = \'$userNamePriv\'"; 
        												
   	my $sth_usernameEonStatus = $dbh->prepare($getUsernameEonStatus);
   	$sth_usernameEonStatus->execute()
   		or database_logger($serverDate, $processEntriesLogfile, $DBI::errstr);
	#Results based on query to get username priority profile
	while (my @results = $sth_usernameEonStatus->fetchrow()) {
		$usernameInEon = $results[0];		
	}
	return $usernameInEon;	
}

## Sub to log errors to file
## @Parms: 	$timeError: TimeString
##			$error_log: Logfile location
##			$entryLine: Line that will be logged
## Return:	None
sub database_logger{
	my $timeError = $_[0];
	my $error_log = $_[1];
	my $entryLine = $_[2];
	open (MYFILE, ">> $error_log");
    print MYFILE "$timeError: $entryLine\n";
    close (MYFILE);
}
