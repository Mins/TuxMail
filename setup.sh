#!/bin/bash

###############################################################################################
# TuxLite Mailserver Script                                                                   #
# Mail stack consists of Postfix MTA + Dovecot for IMAP/POP access                            #
# Spam filtering via DSPAM, Spamhaus RBL, SPF & RDNS checks                                   #
# Users can train DSPAM dictionary by moving mails into Junk folder (when using IMAP)         #
# Configured for security. Encrypted password authentication and TLS/SSL for IMAP & POP3      #
# Mail accounts are virtual, with all mails stored under /home/vmail                          #
# Mail delivery is handled by Dovecot LDA, instead of direct delivery from Postfix            #
###############################################################################################

source ./options.conf

function configure_hostname {

    # Set hostname and FQDN
    sed -i 's/'${SERVER_IP}'.*/'${SERVER_IP}' '${HOSTNAME_FQDN}' '${HOSTNAME}'/' /etc/hosts
    echo "$HOSTNAME" > /etc/hostname
    service hostname start

} # End function basic_server_setup


function install_postfix_dovecot {

    # Install postfix and dovecot
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
    echo "postfix postfix/mailname string $HOSTNAME_FQDN" | debconf-set-selections
    echo "postfix postfix/destinations string localhost.localdomain, localhost" | debconf-set-selections
    aptitude -y install postfix
    aptitude -y install dovecot-common dovecot-imapd dovecot-pop3d dovecot-sieve dspam
    # Install SPF filtering
    aptitude -y install postfix-policyd-spf-python

    # Add a linux user to store virtual domain emails
    # Do not specify a password so that password logins are disabled
    echo ""
    echo "You don't have to input anything to create the vmail user. Simply press enter all the way."
    adduser --uid 5000 --disabled-password vmail

} # End function install_postfix_dovecot


function configure_postfix {

    # Appending config
    # Add basic spam filtering to smtpd_recipient_restrictions
    # Configure virtual domains
    # Virtual domains mapping stored in /etc/postfix/virtual_mailbox_users
    cat ./config/postfix_main.conf >> /etc/postfix/main.cf

    # Enable postfix cram-md5 password format
    echo "mech_list: cram-md5" >> /etc/postfix/sasl/smtpd.conf

    # Increase time out in case a message takes a long time to get processed.
    echo "spf-policyd_time_limit = 3600s" >> /etc/postfix/main.cf

    # Replacing entire master.cf
    # Only allow SASL Auth on port 587, so that mail delivery is not affected when dovecot is down
    # Enable DSPAM filtering using content_filter. Pass emails using lmtp
    # Open port 10034 on localhost to allow reinjection	from DSPAM
    # Uncomment submission line to allow smtps in master.cf
    # Forward incoming mails to dovecot LDA to deliver mails to virtual inboxes
    # so that sieve, quotas and other plugins can be enabled
    # Enable SPF check
    cat ./config/postfix_master.conf > /etc/postfix/master.cf

} # End function configure_postfix


function configure_dovecot {

    # Configure vmail settings
    # Overriding settings in /etc/dovecot/conf.d/10-mail.conf

    # Disable insecure imap and enable secure imaps
    # Overriding settings in /etc/dovecot/conf.d/10-master.conf

    # Disable plain text logins
    # Add cram-md5 to login mechanisms
    # Overriding settings in /etc/dovecot/conf.d/10-auth.conf

    # Specify where the password file is for authenticating virtual domain users
    # Overriding settings in /etc/dovecot/conf.d/10-auth.conf and auth-passwdfile.conf.ext

    # Listen for smtp auth requests
    # Overriding settings in /etc/dovecot/conf.d/10-master.conf

    # Configure LDA to specify userdb socket, and to enable sieve
    # Overriding settings in /etc/dovecot/conf.d/15-LDA.conf

    # From options.conf, Debian = 1, Ubuntu = 2
    if [ $DISTRO -eq 1 ]; then
        cat ./config/dovecot.conf >> /etc/dovecot/dovecot1.conf
    else
        cat ./config/dovecot.conf >> /etc/dovecot/dovecot2.conf
    fi # End if distro == 1


} # End function configure_dovecot


function configure_dspam {

    # Add Trust vmail
    # Disable webstats
    # Uncomment ServerDomainSocketPath "/var/spool/postfix/dspam/dspam.sock"
    # Reinject all mails back to postfix instead of default quarantine
    # Refer to DSPAM manual if you want to learn more about the various settings
    cat ./config/dspam.conf > /etc/dspam/dspam.conf

    # Place DSPAM signature in mail headers instead of message body
    # Reinject all mails back to postfix instead of default quarantine
    cat ./config/dspam_default.prefs.conf > /etc/dspam/default.prefs

    # Since Postfix runs in chroot, create a DSPAM folder
    # to hold the socket for Postfix -> DSPAM (lmtp)
    mkdir /var/spool/postfix/dspam/
    chown dspam:dspam /var/spool/postfix/dspam

    # Need compile tools for this plugin, as the package is not available in repository yet
    #aptitude -y install build-essential dovecot-dev
    #wget http://johannes.sipsolutions.net/download/dovecot-antispam/dovecot-antispam-2.0.tar.bz2
    #tar xjf dovecot-antispam-2.0.tar.bz2
    #cd dovecot-antispam-2.0
    #cp defconfig .config
    # Install dev package to get dovecot headers in /usr/include/dovecot
    #make install
    #cd ../../

    # From options.conf, Debian = 1, Ubuntu = 2
    if [ $DISTRO -eq 1 ]; then
        # Debian is missing antispam package, install it manually from pre-compiled binaries
        if [ $ARCHITECTURE -eq 32 ]; then
            cp ./dovecot-antispam/lib90_antispam_plugin_deb32.so /usr/lib/dovecot/modules/lib90_antispam_plugin.so
        else
            cp ./dovecot-antispam/lib90_antispam_plugin_deb64.so /usr/lib/dovecot/modules/lib90_antispam_plugin.so
        fi
    else
        # Ubuntu 12.04 has antispam package in repo
        aptitude -y install dovecot-antispam
    fi # End if distro == 1

} # End function configure_dspam

function configure_sieve {

    mkdir /var/lib/dovecot/sieve
    # Use a default config that automatically moves junk mails into "Junk" folder
    # based on the results of DSPAM's scan
    cat ./config/sieve_default.conf > /var/lib/dovecot/sieve/default.sieve
    cd /var/lib/dovecot/sieve
    # Compile default sieve rule
    sievec default.sieve
    cd -
}

function configure_fail2ban {

    # First install fail2ban
    aptitude -y install fail2ban

    # Find postfix section and delete the "enabled = false" line
    sed -i '/\[postfix\]/{n;N;d}' /etc/fail2ban/jail.conf
    # Replace with enabled = true
    sed -i 's/\(\[postfix\]\)/\1\n\nenabled  = true/' /etc/fail2ban/jail.conf

    # Add new filter to fail2ban for dovecot
    cat >> /etc/fail2ban/filter.d/dovecot-pop3imap.conf <<EOF
[Definition]
failregex = (?: pop3-login|imap-login): .*(?:Authentication failure|Aborted login \(auth failed|Aborted login \(tried to use disabled|Disconnected \(auth failed).*rip=(?P<host>\S*),.*
ignoreregex =
EOF

    cat >> /etc/fail2ban/jail.conf <<EOF

[dovecot-pop3imap]

enabled  = true
port     = pop3,pop3s,imap,imaps
filter   = dovecot-pop3imap
logpath  = /var/log/mail.log
EOF

    # Configure rsyslog so that fail2ban can work more effectively
    sed -i 's/RepeatedMsgReduction\ on/RepeatedMsgReduction\ off/' /etc/rsyslog.conf

    service rsyslog restart
    service fail2ban restart

    echo "Fail2ban installed and configured successfully."
}

function generate_self_signed_cert {

    openssl req -new -x509 -days 3650 -config ./config/openssl_dovecot.conf -nodes -out /etc/ssl/certs/dovecot.pem -keyout /etc/ssl/private/dovecot.pem
    if [ $? -eq 0 ]; then
        service dovecot restart
        echo "A 10 year cert has been generated and placed in /etc/ssl/certs/dovecot.pem"
    else
        echo "Error generating cert."
    fi
}


# Start main program
if [ ! -n "$1" ]; then
    echo ""

    echo -n "$0"
    echo -ne "\033[36m install\033[0m"
    echo     " - Installs Postfix + Dovecot."

    echo -n "$0"
    echo -ne "\033[36m f2b\033[0m"
    echo     " - Install Fail2ban and configure to protect postfix/dovecot."

    echo -n "$0"
    echo -ne "\033[36m cert\033[0m"
    echo     " - Generate replacement self signed cert for dovecot. New cert valid for 10 years. Default cert lasts 1 year. Edit config/openssl_dovecot.conf before using."

    echo ""
    exit
fi


case $1 in
install)
    apt-get update && apt-get -y install aptitude
    configure_hostname
    install_postfix_dovecot
    configure_postfix
    configure_dovecot
    configure_dspam
    configure_sieve
    service postfix stop
    service postfix start
    service dovecot stop
    service dovecot start
    service dspam stop
    service dspam start
    echo "Mail server configured successfully. Use the admin.sh script to add new mail users & domains."
;;
f2b)
    configure_fail2ban
;;
cert)
    generate_self_signed_cert
;;
esac
