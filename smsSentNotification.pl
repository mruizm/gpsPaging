#!/usr/bin/perl
#SMS Notification for ito-paging 3.0
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
		my $selected_modem = $availableModems[0];
		print "Using modem at $selected_modem\n";
		database_logger($serverDate, $smsModemLog, "Using modem at $selected_modem.");
		#Instructions to gather and send the SMS notifications
		smsAlertsToBeDelivered($selected_modem);
	}
	if ($numberModem eq "1")
	{
	#	my $selected_modem = shift @availableModems;
		print "\nWarning! $numberModem : Just modem at $availableModems[0] is available for SMS delivery!\n";
		database_logger($serverDate, $smsModemLog, "Warning! $numberModem : Just modem at $availableModems[0] is available for SMS delivery!");
		my $selected_modem = $availableModems[0];
		smsAlertsToBeDelivered($selected_modem);
		
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

main();

#Subroutine to process SMS for alerts as "Dispatched"
sub smsAlertsToBeDelivered()
{
	our $dbh = DBI->connect('dbi:mysql:dbname=itopagingdb_staging;port=3306;host=c9t03823.itcs.hp.com','gpspaging','GPSroot2013',{AutoCommit=>0,RaiseError=>0,PrintError=>1});
    my $serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
    my $modem_port = $_[0];
	my $gsm = new Device::Gsm( port => $modem_port );
	my $response = "Y";
	my $smsProcess;
	my $SelectSmsRety_sql;
	my $smsProcessingLog = "/opt/itopaging/smsProcessing.log";
	my $rows;
	my $sms = "";
    
    #Query to get Dispatched Events for SMS delivery
    my $SelectdispatchedEvent_sql = "SELECT entryId, username, phone_number, sms_text, date_added_db FROM ito_sms_to_deliver WHERE was_delivered = \'0\'
    									AND ttyUsb_processed = \'0\'";
    my $sth_events_to_sms = $dbh->prepare($SelectdispatchedEvent_sql);
    $sth_events_to_sms->execute();
    $rows = $sth_events_to_sms->rows;
    $DBI::err && die $DBI::errstr;
    chomp($rows);
    if ($rows eq "0")
    {
    	print "No SMS events found for processing!\n";
    	database_logger($serverDate, $smsProcessingLog, "No Events found for SMS delivery!"); 
    	
    }
    else
    {
		while (my @results = $sth_events_to_sms->fetchrow())
		{
			$serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
			
			my $smsEntryId 		= $results[0];
			my $smsUsername 	= $results[1];
			my $smsPhone 		= $results[2];
			my $smsText			= $results[3];
			my $smsDateAdddedDb = $results[4];
			$gsm->connect();
   			$sms = $gsm->send_sms( recipient => $smsPhone,
                          	  	  	  content   => $smsText);
 			if ($sms)
   			{
				$serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
				my $SmsPrint = "SmsEntry $smsEntryId: SMS $smsText delivered to $smsUsername - $smsPhone";
				print "$SmsPrint\n";
				database_logger($serverDate, $smsProcessingLog, $SmsPrint);
				$smsProcess = "UPDATE ito_sms_to_deliver SET ttyUsb_processed = \'$modem_port\', was_delivered = \'1\' , date_sms_delivered = \'$serverDate\'
    											WHERE entryId = \'$smsEntryId\' AND username = \'$smsUsername\' and date_added_db = \'$smsDateAdddedDb\'";
    		
    			my $sth_smsProcess = $dbh->prepare($smsProcess);
    			$sth_smsProcess->execute();   				
           		$sth_smsProcess->finish()
            		or database_logger($serverDate, $smsProcessingLog, $DBI::errstr);
            	$dbh->commit;
           	}
           	else{
				$serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
				my $SmsPrint = "SmsEntry $smsEntryId: SMS $smsText NOT delivered to $smsUsername - $smsPhone";
				print "$SmsPrint\n";
				database_logger($serverDate, $smsProcessingLog, $SmsPrint);
                $smsProcess = "UPDATE ito_sms_to_deliver SET ttyUsb_processed = \'$modem_port\', was_delivered = \'0\' 
    											WHERE entryId = \'$smsEntryId\' AND username = \'$smsUsername\' and date_added_db = \'$smsDateAdddedDb\'";
    		
    			my $sth_smsProcess = $dbh->prepare($smsProcess);
    			$sth_smsProcess->execute();   				
           		$sth_smsProcess->finish()
            		or database_logger($serverDate, $smsProcessingLog, $DBI::errstr);
            	$dbh->commit;
           	}        
       	}
       	$sth_events_to_sms->finish();       
	}
	## Processing the events which first try was not successfull
	$serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
	my $smsRetryPrint = "Processing entries which were detected to fail first SMS delivert attempt...";
	print "\n$smsRetryPrint";
	database_logger($serverDate, $smsProcessingLog, $smsRetryPrint);
	
	$SelectSmsRety_sql = "SELECT entryId, username, phone_number, sms_text, date_added_db, ttyUsb_processed FROM ito_sms_to_deliver WHERE was_delivered = \'0\'
    									AND ttyUsb_processed LIKE \'%ttyUSB%\'";
    my $sth_events_to_sms_retry = $dbh->prepare($SelectSmsRety_sql);
    $sth_events_to_sms_retry->execute();
    $rows = $sth_events_to_sms_retry->rows;
	chomp($rows);
    $DBI::err && die $DBI::errstr;
    if ($rows eq "0")
    {
    	print "\nNo SMS events found to retry!\n";
    	database_logger($serverDate, $smsProcessingLog, "No SMS events found to retry!"); 
    	
    }
    else{
    	print "\nSMS events found to retry!\n";
    	database_logger($serverDate, $smsProcessingLog, "SMS events found to retry!");
    	while (my @results = $sth_events_to_sms_retry->fetchrow()){
    		my $smsEntryId 		= $results[0];
			my $smsUsername 	= $results[1];
			my $smsPhone 		= $results[2];
			my $smsText			= $results[3];
			my $smsDateAdddedDb = $results[4];
			my $ttyProcessed	= $results[5];
			
			chomp($ttyProcessed);
			
			if ($ttyProcessed eq "/dev/ttyUSB0")
			{
				$gsm = new Device::Gsm( port => "/dev/ttyUSB3" );
				$modem_port = "/dev/ttyUSB3";
			}
			else{
				$gsm = new Device::Gsm( port => "/dev/ttyUSB0" );
				$modem_port = "/dev/ttyUSB0";
			}
			$gsm->connect();
			$sms = $gsm->send_sms( recipient => $smsPhone,
                          	  	  	  content   => $smsText);
            if ($sms){
				$serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
				my $SmsPrint = "SmsEntry $smsEntryId: SMS $smsText delivered to $smsUsername - $smsPhone";
				print "$SmsPrint\n";
				database_logger($serverDate, $smsProcessingLog, $SmsPrint);
				my $smsRetryProcess = "UPDATE ito_sms_to_deliver SET ttyUsb_processed = \'$modem_port\', was_delivered = \'1\' , date_sms_delivered = \'$serverDate\'
    											WHERE entryId = \'$smsEntryId\' AND username = \'$smsUsername\' and date_added_db = \'$smsDateAdddedDb\'";
    		
    			my $sth_smsRetryProcess = $dbh->prepare($smsRetryProcess);
    			$sth_smsRetryProcess->execute();   				
           		$sth_smsRetryProcess->finish()
            			or database_logger($serverDate, $smsProcessingLog, $DBI::errstr);
            	$dbh->commit;
           	}
           	else{
				$serverDate = DateTime->now(time_zone => 'America/Costa_Rica');
				my $SmsPrint = "SmsEntry $smsEntryId: SMS $smsText NOT delivered to $smsUsername - $smsPhone";
				print "$SmsPrint\n";
				database_logger($serverDate, $smsProcessingLog, $SmsPrint);
                $smsProcess = "UPDATE ito_sms_to_deliver SET ttyUsb_processed = \'$modem_port\', was_delivered = \'0\'
    											WHERE entryId = \'$smsEntryId\' AND username = \'$smsUsername\' and date_added_db = \'$smsDateAdddedDb\'";
    		
    			my $sth_smsProcess = $dbh->prepare($smsProcess);
    			$sth_smsProcess->execute();   				
           		$sth_smsProcess->finish()
            		or database_logger($serverDate, $smsProcessingLog, $DBI::errstr);
            	$dbh->commit;
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
