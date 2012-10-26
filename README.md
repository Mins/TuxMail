### TuxMail Readme

TuxMail is a shell script to automate the installation and configuration of 
an email system for Debian/Ubuntu servers. Ideal for those who prefer running 
their own mailservers instead of using Gmail/Outlook etc.

Configured to use encrypted password authentication and TLS/SSL for IMAP & POP3.
Mail accounts are virtual, with all mail accounts stored under /home/vmail.
Mail clients only, web interface (Squirrelmail/Roundcube) not installed.

The following are installed:-

-   Postfix MTA
-   Dovecot for IMAP/POP access
-   DSPAM (content-based spam filter) 
-   Dovecot antispam for training DSPAM
-   Python Postfix Policyd SPF 

### Compatibility

-   Debian 6
-   Ubuntu 11.10 and above

### Usage

First ensure that the MX and A records for your domain have been setup accordingly.

    # Edit options to enter server IP, hostname etc
    nano options.conf

    # Install mail stack
    ./setup.sh install

    # Add new virtual domain
    ./admin.sh ad mydomain.tld

    # Add new user for mydomain.tld
    ./admin.sh au johndoe@mydomain.tld

Use any IMAP (Mutt, Thunderbird etc) compatible client for sending/receiving mails. 

### Spam filtering

Combating spam includes the following measures:-

-   DSPAM
-   Spamhaus Real-time Blackhole List
-   SPF & RDNS checks
-   Various sanity checks on sender's mailserver

Users train DSPAM dictionary by moving mails into Junk folder (when using IMAP). 
DSPAM will become more effective with increasing usage and training.
