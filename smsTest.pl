#!/usr/bin/perl

use strict;
use warnings;
use Device::Gsm;

my $gsm = new Device::Gsm( port => '/dev/ttyUSB0', assume_registered => 1, log => 'file,sentSmsTest.log', loglevel => 'debug' );

## Register to GSM network (you must supply PIN number in above new() call)
#See 'assume_registered' in the new() method documentation
## Send quickly a short text message
if( $gsm->connect(baudrate => 19200) )
{
	while (1)
	{
		while (1)
		{
			my $network_register = $gsm->register();
			if ($network_register)
			{
				last;
			}
		}		
		my $sent = $gsm->send_sms(recipient => $ARGV[0],
									content   => $ARGV[1]);
        if($sent)
        {
        	print "SMS: $recipient $content SENT!";
        	last;
        }
        else
        {
        	print "Retrying delivey of SMS: $recipient $content\n";
        }
	}
}
#else
#{
#	###BACKUP PLAN FOR SMS DELIVERY
#}
