#!/usr/bin/perl

use strict;
use warnings;
use Device::Gsm;
use Device::Modem 1.47;

sub main()
{
	my %ttyUSB_PIN = ( "/dev/ttyUSB0" => "0743",
					   "/dev/ttyUSB3" => "8707");
					   	
	for my $tty_usb (keys %ttyUSB_PIN) 
	{
    	setDatacardSettings($tty_usb, $ttyUSB_PIN{$tty_usb});
    	readMessages($tty_usb, $ttyUSB_PIN{$tty_usb});
	}		
}

sub setDatacardSettings()
{
	my $modem_port = $_[0];
	my $modem_pin = $_[1];	
	my $modem = new Device::Modem( port => $modem_port );
	print "\n";	
	if( $modem->connect( baudrate => 9600 )) 
	{
    	print "Modem at $modem_port connected!\n";
    	print "Checking if modem is locked...";
    	$modem->atsend( 'AT+CPIN?' . Device::Modem::CR );
    	if ( $modem->answer() =~ m/\+CPIN: READY/)
    	{
    		print "\nModem is UNLOCKED\n";
    	}
    	else
    	{
    		print "\nModem at $modem_port LOCKED. Unlocking it...\n";
    		$modem->atsend( 'AT+CPIN=\"$modem_pin\"' . Device::Modem::CR );
    		print $modem->answer()."\n";
  		
    	}
  		print "Sending initial settings to $modem_port...";
  		$modem->send_init_string();
  		$modem->atsend( 'AT+CNMI=0,0,0,0,0' . Device::Modem::CR );
  		#print $modem_01->answer();
  		$modem->atsend( 'AT+CPMS="ME","ME","ME"' . Device::Modem::CR );
  		#print $modem_01->answer()."\n";
  	} 
  	else 
  	{
    	print "Sorry, no connection with serial port $modem_port!\n";
  	}
}

sub readMessages()
{
	my @msg = ();
	my $modem_port = $_[0];
	my $modem_pin = $_[1];
	my $gsm = new Device::Gsm( port => $modem_port );	

	$gsm->connect(port=> $modem_port, pin=> $modem_pin) or die "Can't connect!";

	print "\n";
	print "Messages in SIM $modem_port:\n";
	for( $gsm->messages('ME') )
	{
        my $sender_mobile = $_->sender();
        my $sender_message = $_->content();
        my $sender_message_index = $_->index();
        print "Message number: ", $sender_message_index, " ", $sender_mobile, ': ', $sender_message, "\n";
	}
}

main();
