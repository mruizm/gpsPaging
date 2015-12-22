dateLocal=`date +%H%M_%d%Y`
mv /var/spool/mail/itopager /var/spool/mail/itopager_$dateLocal
touch /var/spool/mail/itopager
chmod 777 /var/spool/mail/itopager
rm -f /opt/itopager/tmp/enote_mail_bytes_staging.tmp
