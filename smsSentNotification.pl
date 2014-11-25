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
#my @oncallPhone = ("+50688457177", "+50660295500", "+50688661958", "+50671097633");
my @oncallPhoneDTV = ("+50688457177");

my $gsm = new Device::Gsm( port => '/dev/ttyUSB0' );
my $dbh = DBI->connect('dbi:mysql:dbname=gpsinternaldb;port=1531;host=g1t4741.austin.hp.com','gpsinternaldb','Welcome-1234');
my $sth;
my $ticket_id_db;
my $ticket_description;
my $update_statement;
my $response = "Y";
my $rv;
my $ticket_wg;
my $sms_to_send;
my $ticket_ttr_percent;

$sth = $dbh->prepare("SELECT ticket_id, ticket_workgroup, sms_message_to_mobile FROM ticket_in_dispatched
            			where ticket_sent_pager = ?");
$sth->execute('N') or die $DBI::errstr;
while (my @results = $sth->fetchrow()) 
{
	$ticket_id_db = $results[0];
	$ticket_wg = $results[1];
	$sms_to_send = $results[2];
	chomp($ticket_id_db);
	chomp($ticket_wg);
	chomp($sms_to_send);
	#print "$ticket_id_db $ticket_wg $sms_to_send\n";
	my $sth_ito = $dbh->prepare("SELECT distinct team_name FROM ito_team_to_workgroup
					WHERE team_workgroup = ? ");
	$sth_ito->execute($ticket_wg) or die $DBI::errstr;	
	while (my @results = $sth_ito->fetchrow())
	{
		my $send_sms_team = $results[0];
		chomp($send_sms_team);
		#print "$send_sms_team\n";
		
		my $sth_mobile = $dbh->prepare("SELECT b.user_mobile from users_info_table b
					where b.user_is_oncall = 'Y' and b.user_team = ?");
		$sth_mobile->execute($send_sms_team) or die $DBI::errstr;
	#	#print "$sms_to_send\n";
	#	#foreach(@oncallPhone)
		while (my @results = $sth_mobile->fetchrow())
		{
			my $mobile_phone = $results[0];
			#print "$mobile_phone\n";
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
		$sth_mobile->finish();
	}
	$sth_ito->finish();
	##print "UPDATE ticket_in_dispatched SET ticket_sent_pager = $rv  WHERE ticket_id = $ticket_id_db\n";
	$update_statement = "UPDATE ticket_in_dispatched SET ticket_sent_pager = ? WHERE ticket_id = ?";
	$rv = $dbh->do($update_statement, undef, $response, $ticket_id_db); 
	$DBI::err && die $DBI::errstr;
}
$sth->finish();

my $sth_info_slo = $dbh->prepare("SELECT ticket_id, ticket_workgroup, sms_message_to_mobile, ticket_subject FROM ticket_with_slo
                    where ticket_sent_pager = ?");
$sth_info_slo->execute('N') or die $DBI::errstr;
while (my @results = $sth_info_slo->fetchrow()) 
{
	$ticket_id_db = $results[0];
	$ticket_wg = $results[1];
	$sms_to_send = $results[2];
	$ticket_ttr_percent = $results[3];
	chomp($ticket_id_db);
	chomp($ticket_wg);
	chomp($sms_to_send);

	my $sth_team_name = $dbh->prepare("SELECT distinct team_name FROM ito_team_to_workgroup
					WHERE team_workgroup = ? ");
	$sth_team_name->execute($ticket_wg) or die $DBI::errstr;	
	
	while (my @results = $sth_team_name->fetchrow())
	{
		my $send_sms_team = $results[0];
		chomp($send_sms_team);
		
		my $sth_mobile_slo = $dbh->prepare("SELECT b.user_mobile from users_info_table b
					where b.user_is_oncall = 'Y' and b.user_team = ?");
		$sth_mobile_slo->execute($send_sms_team) or die $DBI::errstr;
		#print "$sms_to_send\n";
		#foreach(@oncallPhone)
		while (my @results = $sth_mobile_slo->fetchrow())
		{
			my $mobile_phone = $results[0];
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
		$sth_mobile_slo->finish();
	}
	$sth_team_name->finish();
	#print "UPDATE ticket_with_slo SET ticket_sent_pager = $rv  WHERE ticket_id = $ticket_id_db AND ticket_subject = $ticket_description\n";
	$update_statement = "UPDATE ticket_with_slo SET ticket_sent_pager = ? WHERE ticket_id = ? AND ticket_subject = ?";
	$rv = $dbh->do($update_statement, undef, $response, $ticket_id_db, $ticket_ttr_percent); 
	$DBI::err && die $DBI::errstr;
}
$sth_info_slo->finish();

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
