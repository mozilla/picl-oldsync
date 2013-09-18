#!/bin/sh
#
# Build a server-storage webhead node for AWS deployment.

set -e

YUM="yum --assumeyes --enablerepo=epel"

$YUM update
$YUM install python-pip git mercurial

# Add ssh public keys.

git clone https://github.com/mozilla/identity-pubkeys
cd identity-pubkeys
git checkout b63a19a153f631c949e7f6506ad4bf1f258dda69
cat *.pub >> /home/ec2-user/.ssh/authorized_keys
cd ..
rm -rf identity-pubkeys

# Checkout and build latest server-storage.

python-pip install virtualenv

useradd syncstorage

UDO="sudo -u syncstorage"

cd /home/syncstorage
$UDO git clone https://github.com/mozilla-services/server-storage
cd ./server-storage
$UDO git checkout -t origin/rfk/hawkauth

$YUM install openssl-devel libmemcached-devel libevent-devel python-devel gcc
$UDO make build
$UDO ./bin/pip install gunicorn gevent PyMySQL pymysql_sa
$UDO ./bin/pip install repoze.who.plugins.hawkauth
$UDO git checkout rfk/hawkauth            # ugh, `make build` resets this.

# Once that's built, we can replace its server-core dep with a tweaked version.

cd ./deps
rm -rf server-core
git clone https://github.com/mozilla-services/server-core
cd server-core
git checkout -t origin/rfk/picl-tweaks
../../bin/python setup.py develop
cd ../../

# Write the configuration files.

cat > production.ini << EOF
[DEFAULT]
debug = false

[server:main]
use = egg:Paste#http
host = 0.0.0.0
port = 5000

[app:main]
use = egg:SyncStorage
configuration = file:%(here)s/sync.conf

[loggers]
keys = root

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = INFO
handlers = console

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = INFO
formatter = generic

[formatter_generic]
format = %(asctime)s %(levelname)-5.5s [%(name)s][%(threadName)s] %(message)s
EOF
chown syncstorage:syncstorage production.ini

cat > sync.conf << EOF
[storage]
backend = syncstorage.storage.sql.SQLStorage
sqluri = pymysql://sync:syncerific@localhost/sync
standard_collections = true
use_quota = false
pool_size = 2
pool_overflow = 5
pool_recycle = 3600
reset_on_return = true
create_tables = true

[who.identifiers]
plugins = hawk

[who.challengers]
plugins = hawk

[who.authenticators]
plugins = hawk

[who.plugin.hawk]
use = repoze.who.plugins.hawkauth:make_plugin
master_secret = SECRETKEYOHSECRETKEY

[cef]
use = true
file = syslog
vendor = mozilla
version = 0
device_version = 1.3
product = weave

EOF
chown syncstorage:syncstorage sync.conf


# Write a circus config script.

cd ../
cat > sync.ini << EOF
[watcher:syncstorage]
working_dir=/home/syncstorage/server-storage
cmd=bin/gunicorn_paster -k gevent -w 4 production.ini
numprocesses = 1
stdout_stream.class = FileStream
stdout_stream.filename = sync.log
stdout_stream.refresh_time = 0.5
stdout_stream.max_bytes = 1073741824
stdout_stream.backup_count = 3
stderr_stream.class = StdoutStream
EOF
chown syncstorage:syncstorage sync.ini

# Launch the server via circus on startup.

$YUM install czmq-devel zeromq

python-pip install circus

cat > /etc/rc.local << EOF
su -l syncstorage -c '/usr/bin/circusd --daemon /home/syncstorage/sync.ini'
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
            if (\$request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' "\$http_origin";
                add_header 'Access-Control-Allow-Credentials' 'true';
                add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
                add_header 'Access-Control-Max-Age' 1728000;
                add_header 'Access-Control-Allow-Headers' 'DNT,X-Mx-ReqToken,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization,X-Conditions-Accepted';
                add_header 'Content-Type' 'text/plain charset=UTF-8';
                add_header 'Content-Length' 0;
                return 204;
            }
            add_header 'Access-Control-Allow-Origin' "\$http_origin";
            add_header 'Access-Control-Allow-Credentials' 'true';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Access-Control-Allow-Headers' 'DNT,X-Mx-ReqToken,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization,X-Conditions-Accepted';
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
