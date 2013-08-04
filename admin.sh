 #!/bin/sh

source ./options.conf

function add_mail_user {

    check_user_exist
    if [ $? = 0  ]; then
        echo "Error: Mail user already exists, stopping operation."
        echo "Check that user is not in /etc/postfix/virtual_mailbox_users."
        echo "Then remove /home/vmail/$domain/$user directory if it exists."
        exit 1
    fi

    echo "Adding user $user@$domain to /etc/dovecot/passwd. Please enter a password when prompted."
    # First check if passwd file exists. Create one if missing.
    if [ ! -x /etc/dovecot/passwd ]; then
        touch /etc/dovecot/passwd
        chmod 640 /etc/dovecot/passwd
        chown dovecot:dovecot /etc/dovecot/passwd
    fi

    # Use doveadm pw tool to generate cram-md5 password
    # From options.conf, Debian = 1, Ubuntu = 2
    if [ $DISTRO -eq 1 ]; then
        user_password=`dovecotpw`
    else
        user_password=`doveadm pw`
    fi

    echo "$user@$domain:$user_password" >> /etc/dovecot/passwd

    # Create the needed Maildir directories
    echo "Creating user directory /home/vmail/$domain/$user"
    if [ ! -x /home/vmail/$domain ]; then
        mkdir -p /home/vmail/$domain
        chown 5000:5000 /home/vmail/$domain
        chmod 700 /home/vmail/$domain
    fi

    mkdir -p /home/vmail/$domain/$user/Maildir/{cur,new,tmp}
    mkdir -p /home/vmail/$domain/$user/Maildir/.Drafts/{cur,new,tmp}
    mkdir -p /home/vmail/$domain/$user/Maildir/.Sent/{cur,new,tmp}
    mkdir -p /home/vmail/$domain/$user/Maildir/.Junk/{cur,new,tmp}
    mkdir -p /home/vmail/$domain/$user/Maildir/.Trash/{cur,new,tmp}
    chmod -R 0700 /home/vmail/$domain/$user
    chown -R vmail:vmail /home/vmail/$domain/$user

    # Add user to Postfix virtual map file and reload Postfix
    echo "Adding user to /etc/postfix/virtual_mailbox_users"
    echo $mail_user $domain/$user/Maildir/ >> /etc/postfix/virtual_mailbox_users
    postmap /etc/postfix/virtual_mailbox_users

exit 0

}

function remove_mail_user {

    check_user_exist
    if [ $? = 1  ]; then
        echo "Error: Mail user does not exist, stopping operation."
        echo "Check that user is in /etc/postfix/virtual_mailbox_users."
        echo "Then check /home/vmail/$domain/$user directory if it exists."
        exit 1
    fi

    echo "Removing user from /etc/postfix/virtual_mailbox_users"
    sed -i '/\<'${mail_user}'\>/ d' /etc/postfix/virtual_mailbox_users
    postmap /etc/postfix/virtual_mailbox_users

    echo "Removing user from /etc/dovecot/passwd"
    sed -i '/\<'${mail_user}'\>/ d' /etc/dovecot/passwd

    # Remove the  Maildir directories
    echo "Removing user directory /home/vmail/$domain/$user"
    rm -rf /home/vmail/$domain/$user

exit 0

}

function check_user_exist {

    # First time running this script, file not created yet
    if [ ! -e /etc/postfix/virtual_mailbox_users ]; then
        return 1
    fi

    count=`grep $mail_user /etc/postfix/virtual_mailbox_users | wc -l`
    if [ $count -gt 0 ] || [ -d /home/vmail/$domain/$user ]; then
        # If user already exists, return 0
        return 0
    else
        return 1
    fi
}


function add_virtual_domain {

    test_domain=`grep virtual_mailbox_domains /etc/postfix/main.cf | grep -w $domain | wc -l`
    if [ $test_domain -eq 0 ]; then
        # If domain is not in config, line count will be equals to 0
        # Get current virtual_mailbox_domains config and append new domain to it
        vdomains=`grep virtual_mailbox_domains /etc/postfix/main.cf`
        postconf -e "$vdomains $domain"
        echo "Domain added successfully."
    else
        echo "Domain already exists. Nothing added to postfix configuration file."
    fi
}

function remove_virtual_domain {

    test_domain=`grep virtual_mailbox_domains /etc/postfix/main.cf | grep -w $domain | wc -l`
    if [ $test_domain -gt 0 ]; then
        # If domain is in config, line count will be greater than 0
        # Sed removes exact match of domain only. Using \< and \> boundary
        vdomains=`grep virtual_mailbox_domains /etc/postfix/main.cf | sed 's/\<'${domain}'\s*\>//'`
        postconf -e "$vdomains"
        echo "Domain removed successfully."
    else
        echo "Domain does not exist. Please enter a valid domain to remove."
    fi

}


function change_virtual_user_password {

    check_user_exist
    if [ $? = 1  ]; then
        echo "Error: Mail user does not exist, stopping operation."
        echo "Check that user is in /etc/postfix/virtual_mailbox_users."
        echo "Then check /home/vmail/$domain/$user directory if it exists."
        exit 1
    fi

    # Remove user from /etc/dovecot/passwd before adding again
    sed -i '/\<'${mail_user}'\>/ d' /etc/dovecot/passwd

    # Use doveadm pw tool to generate cram-md5 password
    user_password=`doveadm pw`
    echo "$user@$domain:$user_password" >> /etc/dovecot/passwd

}


# Start main program
if [ ! -n "$1" ]; then
    echo ""
    echo -e  "\033[35;1mUse this script to add/remove mail users/domains.\033[0m"
    echo -e  "\033[35;1mAdd your domains first before adding users.\033[0m"
    echo ""

    echo -n "$0"
    echo -ne "\033[36m ad domain\033[0m"
    echo     " - Add new domain to mail server."

    echo -n "$0"
    echo -ne "\033[36m rd domain\033[0m"
    echo     " - Remove existing domain from mail server."
    echo -n "$0"
    echo -ne "\033[36m au username@domain\033[0m"
    echo     " - Add a new user to mail server."

    echo -n "$0"
    echo -ne "\033[36m ru username@domain\033[0m"
    echo     " - Remove existing user from mail server."

    echo -n "$0"
    echo -ne "\033[36m cpw username@domain\033[0m"
    echo     " - Change password of existing user."

    echo ""
    exit
fi

case $1 in
au)
    if [ ! $# = 2 ]; then
        echo "Please enter a new username@domain."
        exit 1
    else
        user=`echo "$2" | cut -f1 -d "@"`
        domain=`echo "$2" | cut -s -f2 -d "@"`
        mail_user=$2
    fi
    add_mail_user
    echo -e "\033[35;1m Varnish now installed and configured with a ${VARNISH_CACHE_SIZE} cache size. \033[0m"
;;
ad)
    if [ ! $# = 2 ]; then
        echo "Please enter a new domain name."
        exit 1
    else
        domain=$2
    fi
    add_virtual_domain
;;
cpw)
    if [ ! $# = 2 ]; then
        echo "Please enter an existing username@domain."
        exit 1
    else
        user=`echo "$2" | cut -f1 -d "@"`
        domain=`echo "$2" | cut -s -f2 -d "@"`
        mail_user=$2
    fi
    change_virtual_user_password
;;
rd)
    if [ ! $# = 2 ]; then
        echo "Please enter an existing domain."
        exit 1
    else
        domain=$2
    fi
    remove_virtual_domain
;;
ru)
    if [ ! $# = 2 ]; then
        echo "Please enter an existing username@domain."
        exit 1
    else
        user=`echo "$2" | cut -f1 -d "@"`
        domain=`echo "$2" | cut -s -f2 -d "@"`
        mail_user=$2
    fi
    remove_mail_user
;;
esac
