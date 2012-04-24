#!/bin/bash
# Installer for GitLab on RHEL 6 (Red Hat Enterprise Linux and CentOS)

# Define the public hostname
export GL_HOSTNAME=$HOSTNAME

# Define gitlab installation root
export GL_INSTALL_ROOT=/var/www/gitlabhq

# Define the version of ruby the environment that we are installing for
export RUBY_VERSION=ruby-1.9.2-p290

# Define the rails environment that we are installing for
export RAILS_ENV=production

die()
{
  # $1 - the exit code
  # $2 $... - the message string

  retcode=$1
  shift
  printf >&2 "%s\n" "$@"
  exit $retcode
}


echo "### Check OS (we check if the kernel release contains el6)"
uname -r | grep "el6" || die 1 "Not RHEL or CentOS"


echo "### Check if we are root"
[[ $EUID -eq 0 ]] || die 1 "This script must be run as root"


echo "### Installing packages"

# Install epel-release
rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-5.noarch.rpm

# Modified list from gitlabhq
yum install -y \
make \
libtool \
openssh-clients \
gcc \
libxml2 \
libxml2-devel \
libxslt \
libxslt-devel \
python-devel \
wget \
readline-devel \
ncurses-devel \
gdbm-devel \
glibc-devel \
tcl-devel \
openssl-devel \
db4-devel \
byacc \
httpd \
gcc-c++ \
curl-devel \
openssl-devel \
zlib-devel \
httpd-devel \
apr-devel \
apr-util-devel \
sqlite-devel \
libicu-devel \
gitolite \
redis \
sudo \
postfix \
mysql-devel


# Lets get some user and other general Admin shite out of the way.

# add a user, make them a system user - call them git.

echo 'Creating the git user' 
/usr/sbin/adduser -r -m --shell /bin/bash --comment 'git version control' git

# Create our ssh key as the git user - lets not mess with this too much

su - git -c 'ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa'

# Ensure correct ownership

/bin/chown git:git -R /home/git/.ssh 

# Make sure that the perms are correct against the .ssh dir

/bin/chmod 0700 /home/git/.ssh


# Exit from the git user once done

# Righto - GitlabHQ and Gitolite integration stuff - We need for the user that runs the webserver to have access to the gitolite admin repo
# we will be adding and removing permissions on this repo.   
# We already have the git user who is the owner of the repo, so we clone his key to make life easier.
# This may not be best practice - but y'know without being too complex this is functional.

# Apache may have to run some things in a shell.  I hate this

echo 'providing apache with a ssh key and permissions to the repositories' 

/usr/sbin/usermod -s /bin/bash -d /var/www/ -G git apache

# Create the keydir for the webserver user (apache)

mkdir /var/www/.ssh

# Copy the git users key, chown that stuff

cp -f /home/git/.ssh/id_rsa* /var/www/.ssh/ && chown apache:apache /var/www/.ssh/id_rsa* && chmod 600 /var/www/.ssh/id_rsa*

# As we will be looping back to localhost only, we grab the local key to avoid issues when its unattended.

/usr/bin/sudo -u apache ssh-keyscan localhost >> /var/www/.ssh/known_hosts

# Apparently we like to be sure who owns what.

/bin/chown apache:apache -R /var/www/.ssh

#END OS SETUP STUFF#

# Lets configure GitlabHQ and gitolite to do our bidding.  

# Change the default umask in gitolite so that repos get created with permissions that allow apache to read them
# Otherwise you will get issues with commits/code/whateveryouexpect not showing up.
# N.B. We make this change against the *example*  config file. 
sed -i 's/0077/0007/g' /usr/share/gitolite/conf/example.gitolite.rc

# Do the heavy lifting.  Configure gitolite and make git the primary admin.

echo 'Setting up Gitolite' 

su - git -c "gl-setup -q /home/git/.ssh/id_rsa.pub"

# Cause we are paranoid about ownership, pimp slap that shit.
  
/bin/chown -R git:git /home/git/
/bin/chmod 770 /home/git/repositories/
/bin/chmod 770 /home/git/
/bin/chmod 600 -R /home/git/.ssh/
/bin/chmod 700 /home/git/.ssh/
/bin/chmod 600 /home/git/.ssh/authorized_keys


echo "### Installing RVM and Ruby"

# Instructions from https://rvm.io
curl -L get.rvm.io | bash -s stable 

# Load RVM
source /etc/profile.d/rvm.sh

# Install Ruby
rvm install $RUBY_VERSION

# Install core gems
gem install rails passenger rake bundler grit --no-rdoc --no-ri


echo "### Install pip and pygments"

yum install -y python-pip
pip-python install pygments


# Clone the gitlabHQ sources to our desired location

echo ' Installing GitlabHQ' 

cd /var/www && git clone https://github.com/gitlabhq/gitlabhq.git

cd $GL_INSTALL_ROOT && bundle install

rvm all do passenger-install-apache2-module -a




##
#  Database setup
#

# Before we do anything, make sure that redis is started

/etc/init.d/redis start
chkconfig redis on

# Lets build the DB and some other jazz
# Do this as the apache user - else shit gets weird

cd $GL_INSTALL_ROOT

source /etc/profile.d/rvm.sh

# Use SQLite
cp config/database.yml.sqlite config/database.yml

# Rename config files
cp config/gitlab.yml.example config/gitlab.yml

# Change gitlabhq hostname to GL_HOSTNAME
sed -i "s/host: localhost/host: $GL_HOSTNAME/g" config/gitlab.yml

rvm all do rake db:setup RAILS_ENV=production
rvm all do rake db:seed_fu RAILS_ENV=production

##
# Finish the setup
#

export PASSENGER_VERSION=`find /usr/local/rvm/gems/$RUBY_VERSION/gems -type d -name "passenger*" | cut -d '-' -f 4`

# Shove everything in to a vhost - I hate Passenger config in the main, it gets in my way
cat > /etc/httpd/conf.d/gitlabhq.conf << EOF
<VirtualHost *:80>
    ServerName $GL_HOSTNAME
    DocumentRoot $GL_INSTALL_ROOT/public
    LoadModule passenger_module /usr/local/rvm/gems/$RUBY_VERSION/gems/passenger-$PASSENGER_VERSION/ext/apache2/mod_passenger.so
    PassengerRoot /usr/local/rvm/gems/$RUBY_VERSION/gems/passenger-$PASSENGER_VERSION
    PassengerRuby /usr/local/rvm/wrappers/$RUBY_VERSION/ruby
    <Directory $GL_INSTALL_ROOT/public>
        AllowOverride all
        Options -MultiViews
    </Directory>
</VirtualHost>
EOF

# Enable virtual hosts in httpd
cat > /etc/httpd/conf.d/enable-virtual-hosts.conf << EOF
NameVirtualHost *:80
EOF

# Ensure that apache owns all of gitlabhq - No shallower
chown -R apache:apache $GL_INSTALL_ROOT

# permit apache the ability to write gem files if needed..  To be reviewed.
chown apache:root -R /usr/local/rvm/gems/

# Allow group access the git home dir - Allows apache in the door
chmod 770 /home/git/
chmod go-w /home/git/

# Slap selinux upside the head
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

# Mod iptables - Allow port 22 and 80 in
sed -i '/--dport 22/ a\-A INPUT -m state --state NEW -m tcp -p tcp --dport 80 -j ACCEPT' /etc/sysconfig/iptables

#Restart iptables.
service iptables restart

# Add httpd to start and start the service
chkconfig httpd on
service httpd start
