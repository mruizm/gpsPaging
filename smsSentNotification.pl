#!/usr/bin/perl
require modemInit;

use strict;
use warnings;
use Device::Gsm;
use DBI;
use POSIX qw(strftime);

sub main()
{
	#Definition of the installed serial port with its PIN code
	my %ttyUSB_PIN = ( "/dev/ttyUSB0" => "0743",
				  	   "/dev/ttyUSB3" => "8707" );
	
	my $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
	print "\n$serverDate : Starting smsSentNotification script...\n";
	print "\n--- Running initial modem validations... ---\n";
	my @availableModems = modemInit::checkAvailableModemsAndUnlock(%ttyUSB_PIN);
	
	if ((my $numberModem = @availableModems) eq "2")
	{
		print "Good! $numberModem : Both modems available for SMS delivery.\n";
		print "\n--- Processing Alerts... ---\n";
		my $selected_modem = $availableModems[0];
		print "Using modem at $selected_modem\n";
		{
			print "\nChecking Dispached Alerts...\n";
			dispatchedAlerts($selected_modem);
			print "\nChecking SLO Alerts...\n";
			sloAlerts($selected_modem);
			print "Checking EON Alerts...\n";
			eonSmsDelivey($selected_modem);
		}
	}
	if ((my $numberModem = @availableModems) eq "1")
	{
		my $selected_modem = shift @availableModems;
		print "Warning! $numberModem : Just modem at @availableModems[0] is available for SMS delivery!\n";
		dispatchedAlerts($selected_modem);
		sloAlerts($selected_modem);
	}
	if ((my $numberModem = @availableModems) eq "0")
	{
		print "Major issue! $numberModem : No modems available for SMS delivery!\n";
	}
	$serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
	print "\n$serverDate : Finalized smsSentNotification script...\n\n";
	print "============================================================\n";
}

#Subroutine to process SMS for alerts as "Dispatched"
sub dispatchedAlerts()
{
	my $dbh = DBI->connect('dbi:mysql:dbname=itopagingdb;port=3306;host=c9t03823.itcs.hp.com','gpspaging','GPSroot2013', {AutoCommit => 1} );
    my $modem_port = $_[0];
	my $gsm = new Device::Gsm( port => $modem_port );
	my $response = "Y";
    
    #Query to get Dispatched Events for SMS delivery
    my $dispatchedEvent_sql = "SELECT ticket_id, ticket_workgroup, sms_message_to_mobile FROM ticket_in_dispatched where ticket_sent_pager = 'N'";
    my $sth = $dbh->prepare($dispatchedEvent_sql);
    $sth->execute();
    my $rows = $sth->rows;
    $DBI::err && die $DBI::errstr;
    if ($rows eq "0")
    {
    	print "No DISPATCHED events found for processing!\n"; 
    }
    else
    {
    	while (my @results = $sth->fetchrow())
    	{
        	my $ticket_id_db = $results[0];
        	my $ticket_wg = $results[1];
        	my $sms_to_send = $results[2];
        	chomp($ticket_id_db);
        	chomp($ticket_wg);
        	chomp($sms_to_send);
        	#print "$ticket_id_db $ticket_wg $sms_to_send\n";
        
        	#Query to get the team_name value from table ito_team_to_workgroup using ticket_workgroup from event
        	my $getEventWorkGroup_sql = "SELECT distinct team_name FROM ito_team_to_workgroup WHERE team_workgroup = \'$ticket_wg\'";
        	#print "$getEventWorkGroup_sql\n";
        	my $sth_ito = $dbh->prepare($getEventWorkGroup_sql);
        	$sth_ito->execute();
        	$DBI::err && die $DBI::errstr;
        	while (my @results = $sth_ito->fetchrow())
        	{
            	my $send_sms_team = $results[0];
            	chomp($send_sms_team);
            
           		#Query to get the mobiles based on team_name from previous quer and from those determine which have the is_dispatched flag as Y
            	my $getMobiles_sql = "SELECT user_mobile FROM users_info_table WHERE user_team = \'$send_sms_team\' 
               					      AND username IN (SELECT username FROM ito_notification_array WHERE is_dispatched = 'Y')";
            	#print "$getMobiles_sql\n";
            	my $sth_mobile = $dbh->prepare($getMobiles_sql);
            	$sth_mobile->execute();
            	my $rows = $sth_mobile->rows;   
            	$DBI::err && die $DBI::errstr;
            	if ($rows eq "0")
            	{
            		print "\nNo mobiles were found to notify SMS Alert: $sms_to_send\n";
            		print "Will automatically ACK the alert(s)...\n";
           			my $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
           			my $update_statement = "UPDATE ticket_in_dispatched SET ticket_sent_pager = 'Y' WHERE ticket_id = $ticket_id_db";
           			my $rv = $dbh->prepare($update_statement);
					$rv = execute();
               		$rv = finish();
               		$DBI::err && die $DBI::errstr;
           			$update_statement = "UPDATE ticket_in_dispatched SET ticket_date_sent_page = $serverDate WHERE ticket_id = $ticket_id_db";
           			$rv = $dbh->prepare($update_statement);
					$rv = execute();
                    $rv = finish();
                    $DBI::err && die $DBI::errstr;
            	}
            	else
            	{
					while (my @results = $sth_mobile->fetchrow())
            		{
               			my $mobile_phone = $results[0];
               			if ( $gsm->connect(baudrate => 9600) )
               			{
                   			my $network_register = $gsm->register();
                   			if ($network_register)
                   			{
                      			my $sms = $gsm->send_sms( recipient => $mobile_phone,
                                               	  	  	  content   => $sms_to_send,);
                      			if ($sms)
                      			{
                          			print "Mobile: $mobile_phone Notification: $sms_to_send\n";
                           			#print "UPDATE ticket_in_dispatched SET ticket_sent_pager = $rv  WHERE ticket_id = $ticket_id_db\n";
                           			my $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
                           			my $update_statement = "UPDATE ticket_in_dispatched SET ticket_sent_pager = ? WHERE ticket_id = ?";
                           			my $rv = $dbh->do($update_statement, undef, $response, $ticket_id_db);
                           			$DBI::err && die $DBI::errstr;
                           			$update_statement = "UPDATE ticket_in_dispatched SET ticket_date_sent_page = ? WHERE ticket_id = ?";
                           			$rv = $dbh->do($update_statement, undef, $serverDate, $ticket_id_db);
	                       			$DBI::err && die $DBI::errstr;
                       			}
                   			}
               			}
               		}
           		}
           		$sth_mobile->finish();
           	}
           	$sth_ito->finish();             
       	}       
	}
	$sth->finish();	
}

#Subroutine to process SMS for alerts as "SLO "
sub sloAlerts()
{
	my $dbh = DBI->connect('dbi:mysql:dbname=itopagingdb;port=3306;host=c9t03823.itcs.hp.com','gpspaging','GPSroot2013', {AutoCommit => 1} );
    my $modem_port = $_[0];
	my $gsm = new Device::Gsm( port => $modem_port );
	my $response = "Y";
	
	#Query to get 50%, 75% and Deadline Events for SMS delivery
	my $sloEvent_sql = "SELECT ticket_id, ticket_workgroup, sms_message_to_mobile, ticket_subject FROM ticket_with_slo WHERE ticket_sent_pager = 'N'";
    my $sth = $dbh->prepare($sloEvent_sql);
    $sth->execute();
    my $rows = $sth->rows;
    $DBI::err && die $DBI::errstr;
    if ($rows eq "0")
    {
    	print "No SLO events found for processing!\n\n";    	
    }
	else
    {
    	while (my @results = $sth->fetchrow())
    	{
        	my $ticket_id_db = $results[0];
        	my $ticket_wg = $results[1];
        	my $ticket_subj = $results[2];
        	my $ticket_ttr_percent = $results[3];
        	chomp($ticket_id_db);
        	chomp($ticket_wg);
        	chomp($ticket_subj);
        	processSloAlerts($dbh, $gsm, $ticket_subj, $ticket_wg, $ticket_id_db)
    	}
    }    
}

sub processSloAlerts
{
	my $dbh_priv = $_[0];
	my $gsm_priv = $_[1];	
	my $ticket_subj_priv = $_[2];
	my $ticket_wg_priv = $_[3];
	my $ticket_id_db_priv = $_[4];
	my $sloColumnToCheck;
	my $response = "Y";	 
	
	if ($ticket_subj_priv =~ m/TT[O|R]\s75\sPercent/)
	{
		$sloColumnToCheck = "is_75_percent";
	}
	if ($ticket_subj_priv =~ m/TT[O|R]\s50\sPercent/)
	{
		$sloColumnToCheck = "is_50_percent";
	}
	if ($ticket_subj_priv =~ m/TT[O|R]\sdeadline/)
	{
		$sloColumnToCheck = "is_deadline";
	}
	
   	my $getTeamName_sql = "SELECT distinct team_name FROM ito_team_to_workgroup WHERE team_workgroup = \'$ticket_wg_priv\'";
    my $sth = $dbh_priv->prepare($getTeamName_sql);
    $sth->execute();
    $DBI::err && die $DBI::errstr;
    while (my @results = $sth->fetchrow())
    {
		my $send_sms_team = $results[0];
        chomp($send_sms_team);
            
        #Query to get the mobiles based on team_name from previous query and from those determine which have the defined slo column flag as Y
        my $getMobiles_sql = "SELECT user_mobile FROM users_info_table WHERE user_team = \'$send_sms_team\' 
							  AND username IN (SELECT username FROM ito_notification_array WHERE $sloColumnToCheck = 'Y')";
		my $sth_mobile = $dbh_priv->prepare($getMobiles_sql);
        $sth_mobile->execute();   
        $DBI::err && die $DBI::errstr; 
        my $rows = $sth_mobile->rows;
        if ($rows eq "0")
        {
        	print "\nNo mobiles were found to notify SMS Alert: $ticket_subj_priv\n";
        }
        else
        {
			while (my @results = $sth_mobile->fetchrow())
        	{
        		my $mobile_phone = $results[0];
				if ( $gsm_priv->connect(baudrate => 9600) )
				{
					my $network_register = $gsm_priv->register();
					if ($network_register)
					{
						my $sms = $gsm_priv->send_sms( recipient => $mobile_phone,
													content   => $ticket_subj_priv,);
 						if ($sms)
						{
							print "Mobile: $mobile_phone Notification: $ticket_subj_priv\n";
 							#print "UPDATE ticket_in_dispatched SET ticket_sent_pager = $rv  WHERE ticket_id = $ticket_id_db\n";
							my $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
 							my $update_statement = "UPDATE ticket_with_slo SET ticket_sent_pager = ? WHERE ticket_id = ?";
                           	my $rv = $dbh_priv->do($update_statement, undef, $response, $ticket_id_db_priv);
                           	$DBI::err && die $DBI::errstr;
                           	$update_statement = "UPDATE ticket_with_slo SET ticket_date_sent_page = ? WHERE ticket_id = ?";
                           	$rv = $dbh_priv->do($update_statement, undef, $serverDate, $ticket_id_db_priv);
                           	$DBI::err && die $DBI::errstr;
		               	}
                   	}
               	}
        	}	
        }            
		$sth_mobile->finish();	
	}
	$sth->finish();
}

#Subroutine to process EON Alerts
sub eonSmsDelivey
{
	my $dbh = DBI->connect('dbi:mysql:dbname=itopagingdb;port=3306;host=c9t03823.itcs.hp.com','gpspaging','GPSroot2013', {AutoCommit => 1} );
    my $modem_port = $_[0];
	my $gsm = new Device::Gsm( port => $modem_port );
	my $response = "Y";
    
    #Query to get Dispatched Events for SMS delivery
    my $dispatchedEvent_sql = "SELECT eon_id, eon_workgroup, eon_sms_message_to_mobile FROM eon_in_dispatched where eon_sent_pager = 'N'";
    my $sth = $dbh->prepare($dispatchedEvent_sql);
    $sth->execute();
    my $rows = $sth->rows;
    $DBI::err && die $DBI::errstr;
    if ($rows eq "0")
    {
    	print "No DISPATCHED EONs found for processing!\n"; 
    }
    else
    {
    	while (my @results = $sth->fetchrow())
    	{
        	my $eon_id_db = $results[0];
        	my $eon_wg = $results[1];
        	my $eon_message = $results[2];
        	chomp($eon_id_db);
        	chomp($eon_wg);
        	chomp($eon_message);
        	#print "$ticket_id_db $ticket_wg $sms_to_send\n";
        
        	#Query to get the team_name value from table ito_team_to_workgroup using eon from event
        	my $getEonWorkGroup_sql = "SELECT distinct team_name FROM ito_team_to_workgroup WHERE team_workgroup = \'$eon_wg\'";
        	#print "$getEventWorkGroup_sql\n";
        	my $sth_ito = $dbh->prepare($getEonWorkGroup_sql);
        	$sth_ito->execute();
        	$DBI::err && die $DBI::errstr;
        	while (my @results = $sth_ito->fetchrow())
        	{
            	my $eon_sms_team = $results[0];
            	chomp($eon_message);
            
           		#Query to get the mobiles based on team_name from previous query and from those determine which have the is_dispatched flag as Y to send EON
            	my $getEonMobiles_sql = "SELECT user_mobile FROM users_info_table WHERE user_team = \'$eon_sms_team\' 
               					      AND username IN (SELECT username FROM ito_notification_array WHERE is_dispatched = 'Y')";
            	#print "$getMobiles_sql\n";
            	my $sth_mobile = $dbh->prepare($getEonMobiles_sql);
            	$sth_mobile->execute();
            	my $rows = $sth_mobile->rows;   
            	$DBI::err && die $DBI::errstr;
            	if ($rows eq "0")
            	{
            		print "\nNo mobiles were found to notify EON SMS Alert: $eon_message\n";
            		print "Will automatically ACK the alert(s)...\n";
           			my $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
           			my $update_statement = "UPDATE eon_in_dispatched SET eon_sent_pager = 'Y' WHERE eon_id = $eon_id_db";
           			my $rv = $dbh->prepare($update_statement);
					$rv = execute();
               		$rv = finish();
               		$DBI::err && die $DBI::errstr;
           			$update_statement = "UPDATE eon_in_dispatched SET eon_date_sent_page = $serverDate WHERE eon_id = $eon_id_db";
           			$rv = $dbh->prepare($update_statement);
					$rv = execute();
                    $rv = finish();
                    $DBI::err && die $DBI::errstr;
            	}
            	else
            	{
					while (my @results = $sth_mobile->fetchrow())
            		{
               			my $mobile_phone = $results[0];
               			if ( $gsm->connect(baudrate => 9600) )
               			{
                   			my $network_register = $gsm->register();
                   			if ($network_register)
                   			{
                      			my $sms = $gsm->send_sms( recipient => $mobile_phone,
                                               	  	  	  content   => $eon_message,);
                      			if ($sms)
                      			{
                          			print "Mobile: $mobile_phone Notification: $eon_message\n";
                           			#print "UPDATE ticket_in_dispatched SET ticket_sent_pager = $rv  WHERE ticket_id = $ticket_id_db\n";
                           			my $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
                           			my $update_statement = "UPDATE eon_in_dispatched SET eon_sent_pager = ? WHERE eon_id = ?";
                           			my $rv = $dbh->do($update_statement, undef, $response, $eon_id_db);
                           			$DBI::err && die $DBI::errstr;
                           			$update_statement = "UPDATE eon_in_dispatched SET eon_date_sent_page = ? WHERE eon_id = ?";
                           			$rv = $dbh->do($update_statement, undef, $serverDate, $eon_id_db);
	                       			$DBI::err && die $DBI::errstr;
                       			}
                   			}
               			}
               		}
           		}
           		$sth_mobile->finish();
           	}
           	$sth_ito->finish();             
       	}       
	}
	$sth->finish();	
}

main();
