#!/bin/sh
#
# Build a server-reg webhead node for AWS deployment.

set -e

YUM="yum --assumeyes --enablerepo=epel"

$YUM update
$YUM install python-pip mercurial

# Checkout and build latest server-reg

python-pip install virtualenv

useradd syncreg

UDO="sudo -u syncreg"

cd /home/syncreg
$UDO hg clone https://hg.mozilla.org/services/server-reg
cd ./server-reg

$YUM install openssl-devel libmemcached-devel libevent-devel python-devel gcc
$UDO make build
$UDO ./bin/pip install gunicorn gevent PyMySQL pymysql_sa

# Write the configuration files.

cat > production.ini << EOF
[DEFAULT]
debug = false

[server:main]
use = egg:Paste#http
host = 0.0.0.0
port = 5000

[app:main]
use = egg:SyncReg
configuration = file:%(here)s/sync.conf
EOF
chown syncreg:syncreg production.ini

cat > sync.conf << EOF

[auth]
backend = services.user.sql.SQLUser
sqluri = pymysql://sync:syncerific@localhost/sync
pool_size = 5
pool_recycle = 3600
create_tables = true


[cef]
use = true
file = syslog
vendor = mozilla
version = 0
device_version = 1.3
product = weave

EOF
chown syncreg:syncreg sync.conf


# Write a circus config script.

cd ../
cat > sync.ini << EOF
[watcher:syncreg]
working_dir=/home/syncreg/server-reg
cmd=bin/gunicorn_paster -k gevent -w 4 production.ini
numprocesses = 1
EOF
chown syncreg:syncreg sync.ini

# Launch the server via circus on startup.

$YUM install czmq-devel zeromq

python-pip install circus

cat > /etc/rc.local << EOF
su -l syncreg -c '/usr/bin/circusd --daemon /home/syncreg/sync.ini'
exit 0
EOF

# Setup nginx as proxy.

$YUM install nginx

cat << EOF > /etc/nginx/nginx.conf
user  nginx;
worker_processes  1;
events {
    worker_connections  20480;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    log_format xff '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                   '\$status \$body_bytes_sent "\$http_referer" '
                   '"\$http_user_agent" XFF="\$http_x_forwarded_for" '
                   'TIME=\$request_time ';
    access_log /var/log/nginx/access.log xff;
    server {
        listen       80 default;
        location / {
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_redirect off;
            proxy_pass http://localhost:5000;
        }
    }
}
EOF

/sbin/chkconfig nginx on
/sbin/service nginx start

# Install and configure local MySQL server.

$YUM install mysql mysql-server

/sbin/chkconfig mysqld on
/sbin/service mysqld start

echo "CREATE USER 'sync' IDENTIFIED BY 'syncerific';" | mysql -u root
echo "CREATE USER 'sync'@'localhost' IDENTIFIED BY 'syncerific';" | mysql -u root
echo "CREATE DATABASE sync;" | mysql -u root
echo "GRANT ALL ON sync.* TO 'sync';" | mysql -u root
