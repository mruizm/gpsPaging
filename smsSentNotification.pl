#!/usr/bin/perl
use strict;
use warnings;
use Device::Gsm;
use DBI;
use POSIX qw(strftime);

my @alerts_to_submit_dispacthed = ();
my %alerts_to_submit_slo;
my $alerts_to_submit_slo;
my @alerts_to_submit_all = ();
#my @oncallPhone = ("+50687259239", "+50688457177", "+50687013491", "+50660295500");
my @oncallPhone = ("+50688457177", "+50660295500", "+50688661958", "+50671097633");
my @oncallPhoneDTV = ("+50688457177");

my $gsm = new Device::Gsm( port => '/dev/ttyUSB0' );
my $dbh = DBI->connect('dbi:mysql:dbname=gpsinternaldb;port=1531;host=g1t4741.austin.hp.com','gpsinternaldb','Welcome-1234');
my $sth;
my $ticket_id_db;
my $ticket_description;
my $update_statement;
my $response = "Y";
my $rv;

$sth = $dbh->prepare("SELECT ticket_id, sms_message_to_mobile FROM ticket_in_dispatched
                    where ticket_sent_pager = ?");
$sth->execute('N') or die $DBI::errstr;
while (my @results = $sth->fetchrow()) 
{
	my $sms_to_send = "ALERT: ".$results[1];
	$ticket_id_db = $results[0];
	chomp($ticket_id_db);
	#print "$sms_to_send\n";
	foreach(@oncallPhone)
	{
		my $mobile_phone = $_;
		if( $gsm->connect() ) 
		{		
			$gsm->register();
			$gsm->send_sms
			(
				recipient => $mobile_phone,
				content   => $sms_to_send
			);		
		}
	}
	#print "UPDATE ticket_in_dispatched SET ticket_sent_pager = $rv  WHERE ticket_id = $ticket_id_db\n";
	$update_statement = "UPDATE ticket_in_dispatched SET ticket_sent_pager = ? WHERE ticket_id = ?";
	$rv = $dbh->do($update_statement, undef, $response, $ticket_id_db); 
	$DBI::err && die $DBI::errstr;

}

$sth = $dbh->prepare("SELECT ticket_id, ticket_subject, sms_message_to_mobile FROM ticket_with_slo
                    where ticket_sent_pager = ?");
$sth->execute('N') or die $DBI::errstr;
while (my @results = $sth->fetchrow()) 
{
	$ticket_id_db = $results[0];
	$ticket_description = $results[1];
	chomp($ticket_id_db);
	chomp($ticket_description);
	my $sms_to_send = "ALERT: ".$results[2];	
	#print "$sms_to_send\n";
	foreach(@oncallPhone)
	{
		my $mobile_phone = $_;
		if( $gsm->connect() ) 
		{		
			$gsm->register();
			$gsm->send_sms
			(
				recipient => $mobile_phone,
				content   => $sms_to_send
			);		
		}
	}
	#print "UPDATE ticket_with_slo SET ticket_sent_pager = $rv  WHERE ticket_id = $ticket_id_db AND ticket_subject = $ticket_description\n";
	$update_statement = "UPDATE ticket_with_slo SET ticket_sent_pager = ? WHERE ticket_id = ? AND ticket_subject = ?";
	$rv = $dbh->do($update_statement, undef, $response, $ticket_id_db, $ticket_description); 
	$DBI::err && die $DBI::errstr;
}

##### DTV ATTENTION PAGES #####
$sth = $dbh->prepare("SELECT att_alert_id, att_sms_alert_subject FROM dtv_attention_pages
                    where att_sent_sms = ?");
$sth->execute('N') or die $DBI::errstr;
while (my @results = $sth->fetchrow()) 
{
	my $dtv_sms_to_send = $results[1];
	my $dtv_id_db = $results[0];
	#print "$dtv_sms_to_send\n";
	chomp($dtv_id_db);
	#print "$sms_to_send\n";
	foreach(@oncallPhoneDTV)
	{
		my $dtv_mobile_phone = $_;
		if( $gsm->connect() ) 
		{		
			$gsm->register();
			$gsm->send_sms
			(
				recipient => $dtv_mobile_phone,
				content   => $dtv_sms_to_send
			);		
		}
	}
	#print "UPDATE ticket_in_dispatched SET ticket_sent_pager = $rv  WHERE ticket_id = $ticket_id_db\n";
	$update_statement = "UPDATE dtv_attention_pages SET att_sent_sms = ? WHERE att_alert_id = ?";
	$rv = $dbh->do($update_statement, undef, $response, $dtv_id_db); 
	$DBI::err && die $DBI::errstr;

}
$sth->finish();
$dbh->disconnect;
