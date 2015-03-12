#!/usr/bin/perl
#SMS Subscription for ito-paging 3.0

require '/opt/itopaging/modemInit.pm';
use strict;
use warnings;
use Device::Gsm;
use DBI;
use POSIX qw(strftime);
use DateTime;

sub main()
{
	#Definition of the installed serial port with its PIN code
	my @ttyUSB_PIN = ("/dev/ttyUSB0", "/dev/ttyUSB3");
	my $modemTest = "/opt/itopaging/modemTests.log";	
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	my $smsModemLog = "/opt/itopaging/smsModemValidations.log";
	
	print "\n$serverDate : Starting smsSentNotification script...\n";
	database_logger($serverDate, $smsModemLog, "Starting smsSentNotification script..."); 
	print "\n--- Running initial modem validations... ---\n";
	database_logger($serverDate, $smsModemLog, "--- Running initial modem validations... ---");
	my @availableModems = modemInit_staging::checkAvailableModemsAndUnlock(@ttyUSB_PIN);
	my $numberModem = scalar @availableModems;
	
	if ($numberModem eq "2")
	{
		print "\nGood! $numberModem : Both modems available for SMS delivery.\n";
		database_logger($serverDate, $smsModemLog, "Good! $numberModem : Both modems available for SMS delivery.");
		print "\n--- Processing Alerts... ---\n";
		database_logger($serverDate, $smsModemLog, "--- Processing Alerts... ---");
		#my $selected_modem = $availableModems[0];
		
		#Instructions to gather and send the SMS notifications
		foreach my $current_modem (@availableModems)
		{
			print "Using modem at $current_modem\n";
			database_logger($serverDate, $smsModemLog, "Using modem at $current_modem.");
			readMessagesAndProcessSubs($current_modem);
		}
		
	}
	if ($numberModem eq "1")
	{
	#	my $selected_modem = shift @availableModems;
		print "\nWarning! $numberModem : Just modem at $availableModems[0] is available for SMS delivery!\n";
		database_logger($serverDate, $smsModemLog, "Warning! $numberModem : Just modem at $availableModems[0] is available for SMS delivery!");
		my $selected_modem = $availableModems[0];
		readMessagesAndProcessSubs($selected_modem);
		
	}
	if ($numberModem eq "0")
	{
		print "\nMajor issue! $numberModem : No modems available for SMS delivery!\n";
		database_logger($serverDate, $smsModemLog, "Major issue! $numberModem : No modems available for SMS delivery!");
	}
	$serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	print "\n$serverDate : Finalized smsSentNotification script...\n\n";
	database_logger($serverDate, $smsModemLog, "Finalized smsSentNotification script...");
	print "============================================================\n";
	database_logger($serverDate, $smsModemLog, "============================================================");
}

#Update subroutine
sub updateSubscription
{
	my $gsm_priv = $_[0];
	my $dbh_priv = $_[1];
	my $sender_mobile_priv = $_[2];
	my $mobile_notif_priv = $_[3];
	my $sender_message_index_priv = $_[4];
	my $subs_table;
	my $update_statement_Notif;
	my $arrayPrioCounter = 0;
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	my $smsUpdateLog = "/opt/itopaging/updateLog.log";
    
    chomp($mobile_notif_priv);
    my $removedDashMobileNotif = $mobile_notif_priv;
    $removedDashMobileNotif =~ s/-//g;
    
   	my @subsPrio = split //, $removedDashMobileNotif;
   	my @subsArray = ("P1_is_0_percent", "P2_is_0_percent", "P3_is_0_percent", "P4_is_0_percent",
   					 "P1_is_50_percent", "P2_is_50_percent", "P3_is_50_percent", "P4_is_50_percent",
   					 "P1_is_75_percent", "P2_is_75_percent", "P3_is_75_percent", "P4_is_75_percent",
   					 "P1_is_100_percent", "P2_is_100_percent", "P3_is_100_percent", "P4_is_100_percent");
   	
   	# Process SMS subscription digits
   	foreach my $SloPrioBinary (@subsPrio){
   		my $subArrayValur = $subsArray[$arrayPrioCounter];
   		$update_statement_Notif = "UPDATE users_to_notification_array SET $subArrayValur =  \'$SloPrioBinary\' WHERE username = (SELECT username from users_info_table
    							 	WHERE user_mobile = $sender_mobile_priv)";
    	my $sth_UpdateProcess = $dbh_priv->prepare($update_statement_Notif);
    	$sth_UpdateProcess->execute();   				
        $sth_UpdateProcess->finish()
        	or database_logger($serverDate, $smsUpdateLog, $DBI::errstr);
        $dbh_priv->commit;
    	$arrayPrioCounter++;   		
   	}
   	
   	#Update last SMS update
   	my $update_lastNotif = "UPDATE users_info_table SET last_sms_subscribe_update =  \'$serverDate\' WHERE user_mobile = \'$sender_mobile_priv\'";
    my $sth_lastNotif = $dbh_priv->prepare($update_lastNotif);
    $sth_lastNotif->execute();   				
    $sth_lastNotif->finish()
    or database_logger($serverDate, $smsUpdateLog, $DBI::errstr);
    	$dbh_priv->commit;
    		
	$gsm_priv->connect();
	database_logger($serverDate, $smsUpdateLog, "Sending Message: $mobile_notif_priv to $sender_mobile_priv");
    print "Sending Message: $mobile_notif_priv to $sender_mobile_priv\n";
    my $sent = $gsm_priv->send_sms( recipient => $sender_mobile_priv,
                    	 content   => $mobile_notif_priv);
    if ($sent)
    {
    	database_logger($serverDate, $smsUpdateLog, "Subscription processed for mobile: $sender_mobile_priv");
    	print "Subscription processed for mobile: $sender_mobile_priv\n\n";
    	$gsm_priv->delete_sms($sender_message_index_priv, 'ME');
    } 
    else
    {
    	database_logger($serverDate, $smsUpdateLog, "Issues while sending the SMS to $sender_mobile_priv");
    	print "Issues while sending the SMS to $sender_mobile_priv\n\n";
    }
       
}

sub readMessagesAndProcessSubs()
{
	my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	my $modem_port = $_[0];
	my $gsm = new Device::Gsm( port => $modem_port );
	my $readLogFile = "/opt/itopaging/smsSubscriptioReadProcess.log";
		
	my $dbh = DBI->connect('dbi:mysql:dbname=itopagingdb_staging;port=3306;host=c9t03823.itcs.hp.com','gpspaging','GPSroot2013', {AutoCommit => 0} );
	my $sth;
	
	my $mobile_sub_not_found = "SUBSCRIPTION_NOTFOUND";

	$gsm->connect(port=> $modem_port);
	print "\n";
	print "Processing subcription in SIM messages at $modem_port:\n";
	for( $gsm->messages('ME') )
	{
        my $sender_mobile = $_->sender();
        my $sender_message = $_->content();
        my $sender_message_index = $_->index();
        
        #Removes unsolicited 1150 number messages
        if (($sender_mobile eq "1150") || ($sender_mobile eq "kolbiklub"))
        {
        	print "Removing SMS: $sender_mobile - $sender_message\n";
        	$gsm->delete_sms($sender_message_index, 'ME');
        	database_logger($serverDate, $readLogFile, "Removing SMS: $sender_mobile - $sender_message");
        }
        print "Checking sender's mobile in database...\n";
        print "Sender's mobile: $sender_mobile\n";
    	$sth = $dbh->prepare("SELECT count(*) AS COUNT FROM users_info_table
                          	  WHERE user_mobile = ?");
    	$sth->execute($sender_mobile)
    		or database_logger($serverDate, $readLogFile, $DBI::errstr);
    	my $count = $sth->fetchrow_array;
    	print "$count record found!\n";
    	
    	#Removes modem message if number not found in database and it's different than 1150
    	if (($count == 0) && ($sender_mobile != "1150") )
    	{
        	print "Username not FOUND in DB: $sender_mobile - $sender_message\n";
        	database_logger($serverDate, $readLogFile, "Username not FOUND in DB: $sender_mobile - $sender_message");
        	$gsm->send_sms(recipient => $sender_mobile,
                           content   => $mobile_sub_not_found);
            $gsm->delete_sms($sender_message_index, 'ME');
        }
        else
        {
        	$sth = $dbh->prepare("SELECT user_mobile FROM users_info_table
                              	  WHERE user_mobile = ?");
        	$sth->execute($sender_mobile)
        		or database_logger($serverDate, $readLogFile, $DBI::errstr);
        	while (my @results = $sth->fetchrow())
        	{
        		print "Username FOUND in DB: $sender_mobile - $sender_message\n";
        		database_logger($serverDate, $readLogFile, "Username FOUND in DB: $sender_mobile - $sender_message");
        		my $db_retrieved_mobile = $results[0];
        		print "Mobile in DB: $db_retrieved_mobile!\n";
        		updateSubscription($gsm, $dbh, $sender_mobile, $sender_message, $sender_message_index);        		
        	}
        }
	}         
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
main();
