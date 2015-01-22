#!/usr/bin/perl
package modemInit;
use strict;
use warnings;
use Device::Gsm;
use DBI;
use POSIX qw(strftime);

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
1;
