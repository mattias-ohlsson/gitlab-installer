gitlab-installer
================

### Installer for GitLab/GitLabHQ on RHEL 5 and 6 (Red Hat Enterprise Linux and CentOS) ###

- Fully unattended
- MySQL or SQLite database (defaulting to MySQL)
- Localhost mail relay

### Install on EL6 ###

    curl https://raw.github.com/mattias-ohlsson/gitlab-installer/master/gitlab-install-el6.sh | bash

### Install on EL5 ###

    curl https://raw.github.com/mattias-ohlsson/gitlab-installer/master/gitlab-install-el5.sh | bash

### Check status (diagnostic) ###

    su -s /bin/bash apache -c 'bundle exec rake gitlab:app:status RAILS_ENV=production'

### Donate if you like it ###

Flattr [my profile](https://flattr.com/profile/mattiasohlsson "Mattias Ohlsson on Flattr") to support this!
