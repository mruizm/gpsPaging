#!/usr/bin/perl

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
	print "\n$serverDate : Starting smsSubscription script...\n";
	print "\n--- Running initial modem validations... ---\n";
	my @availableModems = checkAvailableModemsAndUnlock(%ttyUSB_PIN);
	
	if ((my $numberModem = @availableModems) eq "2")
	{
		print "Good! $numberModem : Both modems available for SMS delivery.\n";
		print "\n--- Checking for new messages in detected modems... ---\n ";
		foreach (@availableModems)
		{
			print "\nChecking messages in modem at $_...\n";
			readMessagesAndProcessSubs($_);
		}
	}
	if ((my $numberModem = @availableModems) eq "1")
	{
		print "Warning! $numberModem : Just modem at @availableModems[0] is available for SMS delivery!\n";
	}
	if ((my $numberModem = @availableModems) eq "0")
	{
		print "Major issue! $numberModem : No modems available for SMS delivery!\n";
	}
	$serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
	print "\n$serverDate : Finalized smsSubscription script...\n";
	print "============================================================\n";
}

#Sub that check the available modems and unlock them if needed
sub checkAvailableModemsAndUnlock()
{
	my %hash_ttyUSB_PIN = @_;
	my $responseModem;
	my $ini_string = "ATQ0 S0=0 Q0 V1 E1 &C1 &D2 +FCLASS=0";	
	my @workingModems = ();
				   	   
	print "\nChecking configured modems...\n";
	for my $tty_usb ( keys %hash_ttyUSB_PIN ) 
	{
		my $modem_port = $tty_usb;
		my $modem_pin = $hash_ttyUSB_PIN{$tty_usb};
		my $gsm    = new Device::Gsm( port => $modem_port, 
								  	  assume_registered => 1, 
								  	  log => 'file,sentSms.log', 
								  	  loglevel => 'debug', 
								  	  pin => $modem_pin );		
		if ( $gsm->connect() )
		{
			print "\nConnected to $modem_port.\n";
			print "Sending init string ...\n";
			if ($responseModem = $gsm->send_init_string($ini_string))
			{
				print "Modem at $tty_usb responding OK.\n";
				#print "$tty_usb $modem_pin\n";
				#unlockModems() sub call
				unlockModems( $tty_usb, $modem_pin );
				#Think add the working modems in a DB and get one as primary to send the sms
				push ( @workingModems, $tty_usb )
			}
			#else
			#{
			#	print "Modem at $tty_usb not responding. Will notify it.\n";
			#}
		}		
	}
	return (@workingModems);
}

#Unlock subroutine
sub unlockModems()
{
    my $modem_port = $_[0];
    my $modem_pin = $_[1];
    my $modem = new Device::Modem( port => $modem_port );
    print "\nChecking if modem at $modem_port is locked...";
    $modem->connect();
    $modem->atsend( 'AT+CPIN?' . Device::Modem::CR );
    if ( $modem->answer() =~ m/\+CPIN: READY/)
    {
    	print "\nModem at $modem_port is UNLOCKED!\n";
    }
    else
    {
    	print "\nModem at $modem_port LOCKED. Unlocking it...\n";
    	$modem->atsend( 'AT+CPIN=\"$modem_pin\"' . Device::Modem::CR );
    	print $modem->answer()."\n";
  	}
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
	my $update_statement;	
    
    #my $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
    my @subDigits = split //, $mobile_notif_priv;
    
    my @ito_notif_options = ("is_dispatched", "is_50_percent", "is_75_percent", "is_deadline");
    
    #Routine that updates escalation profile for a registered user
    print "\n--- Updating $sender_mobile_priv subscription ---\n";
    foreach my $subs_binary (@subDigits)
    {
    	my $subs_column = shift @ito_notif_options;
    	#print "$subs_binary $subs_table\n"; 
  		if ( $subs_binary == 0 )
    	{
    		$update_statement = "UPDATE ito_notification_array SET $subs_column = 'N' WHERE username = (SELECT username from users_info_table
    							 WHERE user_mobile = $sender_mobile_priv)";
    		my $rv = $dbh_priv->prepare($update_statement);
    		$rv->execute();
    		$rv->finish();
    	#	print "$update_statement\n";
    		$DBI::err && die $DBI::errstr;    		
    	}
    	else
    	{
    		$update_statement = "UPDATE ito_notification_array SET $subs_column = 'Y' WHERE username = (SELECT username from users_info_table
    							 WHERE user_mobile = $sender_mobile_priv)";
    		my $rv = $dbh_priv->prepare($update_statement);
    		$rv->execute();
    		$rv->finish();
		#	print "$update_statement\n";
    		$DBI::err && die $DBI::errstr;    		
    	}
    }
    		
    $gsm_priv->register();
    print "Sending Message: $mobile_notif_priv to $sender_mobile_priv\n";
    my $sent = $gsm_priv->send_sms( recipient => $sender_mobile_priv,
                    	 content   => $mobile_notif_priv);
    if ($sent)
    {
    	print "Subscription processed for mobile: $sender_mobile_priv\n\n";
    	$gsm_priv->delete_sms($sender_message_index_priv, 'ME');
    } 
    else
    {
    	print "Issues while sending the SMS to $sender_mobile_priv\n\n";
    }
       
}

sub readMessagesAndProcessSubs()
{
	my @msg = ();
	my $modem_port = $_[0];
	my $gsm = new Device::Gsm( port => $modem_port );
		
	my $dbh = DBI->connect('dbi:mysql:dbname=itopagingdb;port=3306;host=c9t03823.itcs.hp.com','gpspaging','GPSroot2013', {AutoCommit => 1} );
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
        	$gsm->delete_sms($sender_message_index, 'ME');
        }
        print "Checking sender's mobile in database...\n";
        print "Sender's mobile: $sender_mobile\n";
    	$sth = $dbh->prepare("SELECT count(*) as count FROM users_info_table
                          	  where user_mobile = ?");
    	$sth->execute($sender_mobile) or die $DBI::errstr;
    	my $count = $sth->fetchrow_array;
    	print "$count record found!\n";
    	
    	#Removes modem message if number not found in database and it's different than 1150
    	if (($count == 0) && ($sender_mobile != "1150") )
    	{
            $gsm->register();
            $gsm->send_sms(recipient => $sender_mobile,
                           content   => $mobile_sub_not_found);
             $gsm->delete_sms($sender_message_index, 'ME');
        }
        else
        {
        	$sth = $dbh->prepare("SELECT user_mobile FROM users_info_table
                              	  where user_mobile = ?");
        	$sth->execute($sender_mobile) or die $DBI::errstr;
        	while (my @results = $sth->fetchrow())
        	{
        		my $db_retrieved_mobile = $results[0];
        		print "Mobile in DB: $db_retrieved_mobile!\n";
        		updateSubscription($gsm, $dbh, $sender_mobile, $sender_message, $sender_message_index);        		
        	}
        }
	}         
}
main();
