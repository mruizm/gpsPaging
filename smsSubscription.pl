#!/usr/bin/perl

use strict;
use warnings;
use Device::Gsm;
use DBI;
use POSIX qw(strftime);

my @msg = ();
my $gsm = new Device::Gsm( port => '/dev/ttyUSB0' );
$gsm->connect(port=>'/dev/ttyUSB0') or die "Can't connect!";
my $dbh = DBI->connect('dbi:mysql:dbname=gpsinternaldb;port=1531;host=g1t4741.austin.hp.com','gpsinternaldb','Welcome-1234');
my $sth;
my $mobile_not_found = "";
my $mobile_subs_on = "SUBSCRIPTION_ON";
my $mobile_subs_off = "SUBSCRIPTION_OFF";
my $mobile_subs_not_found = "SUBSCRIPTION_NOTFOUND";
my $response_on = 'Y';
my $response_off = 'N';
my $serverDate = "";
my $sms_to_send;
my $count = 0;


print "Messages in SIM\n";
my $message_number = 0;
for( $gsm->messages('SM') )
{
        my $sender_mobile = $_->sender();
        my $sender_message = $_->content();
    print "Sender: $sender_mobile\n";
    $sth = $dbh->prepare("SELECT count(*) as count FROM users_info_table
                                where user_mobile = ?");
        $sth->execute($sender_mobile) or die $DBI::errstr;
        $count = $sth->fetchrow_array;
        print "$count\n";
        if ($count == 0)
        {
                if( $gsm->connect() )
                {
                        $gsm->register();
                        $gsm->send_sms
                        (
                                recipient => $sender_mobile,
                                content   => $mobile_subs_not_found
                        );
                }
                $gsm->delete_sms($message_number, 'SM');
                $sth->finish();

        }
        else
        {
                $sth = $dbh->prepare("SELECT user_mobile FROM users_info_table
                                where user_mobile = ?");
        $sth->execute($sender_mobile) or die $DBI::errstr;
                while (my @results = $sth->fetchrow())
                {
                        my $db_retrieved_mobile = $results[0];
                        print "Mobile in DB: $db_retrieved_mobile\n";
                        if ($count == 0)
                        {
                                if( $gsm->connect() )
                                {
                                        $gsm->register();
                                        $gsm->send_sms
                                        (
                                                recipient => $sender_mobile,
                                                content   => $mobile_subs_not_found
                                        );
                                }
                        }
                        else
                        {
                                if ($sender_message eq "SUBSCRIPTION_ON")
                                {
                                        $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
                                        my $update_statement = "UPDATE users_info_table SET user_is_oncall = ?, last_sms_subscribe_on = ? WHERE user_mobile = ?";
                                        my $rv = $dbh->do($update_statement, undef, $response_on, $serverDate, $sender_mobile);
                                        $DBI::err && die $DBI::errstr;
                                        if( $gsm->connect() )
                                        {
                                                $gsm->register();
                                                $gsm->send_sms
                                                (
                                                        recipient => $sender_mobile,
                                                        content   => $mobile_subs_on
                                                );
                                        }
                                }
                                if ($sender_message eq "SUBSCRIPTION_OFF")
                                {
                                        $serverDate = strftime("%m/%d/%Y %I:%M %p", localtime());
                                        my $update_statement = "UPDATE users_info_table SET user_is_oncall = ?, last_sms_subscribe_off = ? WHERE user_mobile = ?";
                                        my $rv = $dbh->do($update_statement, undef, $response_off, $serverDate, $sender_mobile);
                                        $DBI::err && die $DBI::errstr;
                                        if( $gsm->connect() )
                                        {
                                                $gsm->register();
                                                $gsm->send_sms
                                                (
                                                        recipient => $sender_mobile,
                                                        content   => $mobile_subs_off
                                                );
                                        }
                                }
                        }
                        $gsm->delete_sms($message_number, 'SM');
                }
        }
        #print "Message number:", $message_number, " ", $sender_mobile, ': ', $sender_message, "\n";
        $message_number++;
}
#Removal of unnecesarry SMS
#for (0 .. 9)
#{
#       $gsm->delete_sms($_, 'SM');
#}
