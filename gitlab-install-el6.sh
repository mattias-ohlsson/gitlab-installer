#!/bin/bash
# Installer for GitLab on RHEL 6 (Red Hat Enterprise Linux and CentOS)
# mattias.ohlsson@inprose.com
#
# Only run this on a clean machine. I take no responsibility for anything.
#
# Submit issues here: github.com/mattias-ohlsson/gitlab-installer

# Define the public hostname
export GL_HOSTNAME=$HOSTNAME

# Install from this GitLab branch
export GL_GIT_BRANCH="5-2-stable"

# Define the version of ruby the environment that we are installing for
export RUBY_VERSION="1.9.3-p392"

# Define MySQL root password
MYSQL_ROOT_PW=$(cat /dev/urandom | tr -cd [:alnum:] | head -c ${1:-16})

# Exit on error

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
uname -r | grep "el6" || die 1 "Not RHEL or CentOS 6 (el6)"

# Install base packages
yum -y install git

## Install epel-release
yum -y install http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm

# Ruby
## packages (from rvm install message):
yum -y install patch gcc-c++ readline-devel zlib-devel libffi-devel openssl-devel make autoconf automake libtool bison libxml2-devel libxslt-devel libyaml-devel

## Install rvm (instructions from https://rvm.io)
curl -L get.rvm.io | bash -s stable

## Load RVM
source /etc/profile.d/rvm.sh

## Fix for missing psych
## *It seems your ruby installation is missing psych (for YAML output).
## *To eliminate this warning, please install libyaml and reinstall your ruby.
## Run rvm pkg and add --with-libyaml-dir
rvm pkg install libyaml

## Install Ruby (use command to force non-interactive mode)
command rvm install $RUBY_VERSION --with-libyaml-dir=/usr/local/rvm/usr
rvm --default use $RUBY_VERSION

## Install core gems
gem install bundler

# Users

## Create a git user for Gitlab
adduser --system --create-home --comment 'GitLab' git

# GitLab Shell

## Clone gitlab-shell
su - git -c "git clone https://github.com/gitlabhq/gitlab-shell.git"

## Edit configuration
su - git -c "cp gitlab-shell/config.yml.example gitlab-shell/config.yml"

## Run setup
su - git -c "gitlab-shell/bin/install"

### Fix wrong mode bits
chmod 600 /home/git/.ssh/authorized_keys
chmod 700 /home/git/.ssh

# Database

## Install redis
yum -y install redis

## Start redis
service redis start

## Automatically start redis
chkconfig redis on

## Install mysql-server
yum install -y mysql-server

## Turn on autostart
chkconfig mysqld on

## Start mysqld
service mysqld start

### Create the database
echo "CREATE DATABASE IF NOT EXISTS gitlabhq_production DEFAULT CHARACTER SET 'utf8' COLLATE 'utf8_unicode_ci';" | mysql -u root

## Set MySQL root password in MySQL
echo "UPDATE mysql.user SET Password=PASSWORD('$MYSQL_ROOT_PW') WHERE User='root'; FLUSH PRIVILEGES;" | mysql -u root

# GitLab

## Clone GitLab
su - git -c "git clone https://github.com/gitlabhq/gitlabhq.git gitlab"

## Checkout
su - git -c "cd gitlab;git checkout $GL_GIT_BRANCH"

## Configure GitLab

cd /home/git/gitlab

### Copy the example GitLab config
su git -c "cp config/gitlab.yml.example config/gitlab.yml"

### Change gitlabhq hostname to GL_HOSTNAME
sed -i "s/  host: localhost/  host: $GL_HOSTNAME/g" config/gitlab.yml

### Change the from email address
sed -i "s/from: gitlab@localhost/from: gitlab@$GL_HOSTNAME/g" config/gitlab.yml

### Copy the example Unicorn config
su git -c "cp config/unicorn.rb.example config/unicorn.rb"

### Listen on localhost:3000
sed -i "s/^listen/#listen/g" /home/git/gitlab/config/unicorn.rb
sed -i "s/#listen \"127.0.0.1:8080\"/listen \"127.0.0.1:3000\"/g" /home/git/gitlab/config/unicorn.rb

### Copy database congiguration
su git -c "cp config/database.yml.mysql config/database.yml"

### Set MySQL root password in configuration file
sed -i "s/secure password/$MYSQL_ROOT_PW/g" config/database.yml

### Configure git user
su git -c 'git config --global user.name  "GitLab"'
su git -c 'git config --global user.email "gitlab@$GL_HOSTNAME"'

# Install Gems

## Install Charlock holmes
yum -y install libicu-devel
gem install charlock_holmes --version '0.6.9'

## For MySQL
yum -y install mysql-devel
su git -c "bundle install --deployment --without development test postgres"

# Initialise Database and Activate Advanced Features
# Force it to be silent (issue 31)
export force=yes
su git -c "bundle exec rake gitlab:setup RAILS_ENV=production"

## Install init script
curl --output /etc/init.d/gitlab https://raw.github.com/gitlabhq/gitlab-recipes/master/init.d/gitlab-centos
chmod +x /etc/init.d/gitlab

## Fix for issue 30
# bundle not in path (edit init-script).
# Add after ". /etc/rc.d/init.d/functions" (row 17).
sed -i "17 a source /etc/profile.d/rvm.sh\nrvm use $RUBY_VERSION" /etc/init.d/gitlab

### Enable and start
chkconfig gitlab on
service gitlab start

# Apache

## Install
yum -y install httpd
chkconfig httpd on

## Configure
cat > /etc/httpd/conf.d/gitlab.conf << EOF
ProxyPass / http://127.0.0.1:3000/
ProxyPassReverse / http://127.0.0.1:3000/
ProxyPreserveHost On
EOF

### Configure SElinux
setsebool -P httpd_can_network_connect 1

## Start
service httpd start

#  Configure iptables

## Open port 80
iptables -I INPUT -p tcp -m tcp --dport 80 -j ACCEPT

## Save iptables
service iptables save

echo "### Done ###############################################"
echo "#"
echo "# You have your MySQL root password in this file:"
echo "# /home/git/gitlab/config/database.yml"
echo "#"
echo "# Point your browser to:" 
echo "# http://$GL_HOSTNAME (or: http://<host-ip>)"
echo "# Default admin username: admin@local.host"
echo "# Default admin password: 5iveL!fe"
echo "#"
echo "# Flattr me if you like this! https://flattr.com/profile/mattiasohlsson"
echo "###"
