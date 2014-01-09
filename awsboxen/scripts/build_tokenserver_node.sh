#!/bin/sh
#
# Build a tokenserver webhead node for AWS deployment.

set -e

YUM="yum --assumeyes --enablerepo=epel"

$YUM update
$YUM install python-pip git

# Add ssh public keys.

git clone https://github.com/mozilla/identity-pubkeys
cd identity-pubkeys
git checkout b63a19a153f631c949e7f6506ad4bf1f258dda69
cat *.pub >> /home/ec2-user/.ssh/authorized_keys
cd ..
rm -rf identity-pubkeys

# Checkout and build latest tokenserver.

python-pip install virtualenv

useradd synctoken

UDO="sudo -u synctoken"

cd /home/synctoken
$UDO git clone https://github.com/mozilla-services/tokenserver.git
cd ./tokenserver

$YUM install openssl-devel libmemcached-devel libevent-devel python-devel
$YUM install gcc gcc-c++ czmq-devel zeromq

$UDO make build CHANNEL=dev
$UDO ./bin/pip install gunicorn PyMySQL pymysql_sa
$UDO ./bin/pip install https://github.com/mozilla-services/wimms/archive/master.tar.gz

# Write the configuration files.

cat > ./etc/production.ini << EOF
[global]
logger_name = tokenserver
debug = false

[server:main]
use = egg:Paste#http
host = 0.0.0.0
port = 5000

[pipeline:main]
pipeline = catcherrorfilter
           tokenserverapp

[filter:catcherrorfilter]
paste.filter_app_factory = mozsvc.middlewares:make_err_mdw

[app:tokenserverapp]
use = egg:tokenserver
mako.directories = cornice:templates
pyramid.reload_templates = true
pyramid.debug = false

[loggers]
keys = root, tokenserver, mozsvc, wimms

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = INFO
handlers = console

[logger_tokenserver]
level = INFO
handlers = console
qualname = tokenserver

[logger_mozsvc]
level = INFO
handlers = console
qualname = mozsvc

[logger_wimms]
level = INFO
handlers = console
qualname = wimms

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = INFO
formatter = generic

[formatter_generic]
format = %(asctime)s %(levelname)-5.5s [%(name)s][%(threadName)s] %(message)s

[tokenserver]
applications = sync-1.1
secrets_file = ./etc/secrets
backend = tokenserver.assignment.sqlnode.SQLNodeAssignment
sqluri = pymysql://token:tokenizationing@localhost/token
create_tables = true
pool_size = 5
token_duration = 31536000

[endpoints]
sync-1.1 = {node}/1.1/{uid}

[browserid]
backend = tokenserver.verifiers.RemoteVerifier
audiences = http://auth.{"Ref":"DNSPrefix"}.dev.lcip.org

EOF
chown synctoken:synctoken ./etc/production.ini


cat > ./etc/secrets << EOF
http://db1.{"Ref":"DNSPrefix"}.dev.lcip.org,123456:SECRETKEYOHSECRETKEY
EOF
chown synctoken:synctoken ./etc/secrets


# Write a circus config script.

cd ../
cat > tokenserver.ini << EOF
[watcher:tokenserver]
working_dir=/home/synctoken/tokenserver
cmd=bin/gunicorn_paster -k gevent -w 4 ./etc/production.ini
numprocesses = 1
stdout_stream.class = FileStream
stdout_stream.filename = sync.log
stdout_stream.refresh_time = 0.5
stdout_stream.max_bytes = 1073741824
stdout_stream.backup_count = 3
stderr_stream.class = FileStream
stderr_stream.filename = sync.err
stderr_stream.refresh_time = 0.5
stderr_stream.max_bytes = 1073741824
stderr_stream.backup_count = 3
EOF
chown synctoken:synctoken tokenserver.ini

# Launch the server via circus on startup.

python-pip install circus

cat > /etc/rc.local << EOF
su -l synctoken -c '/usr/bin/circusd --daemon /home/synctoken/tokenserver.ini'
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

echo "CREATE USER 'token'@'localhost' IDENTIFIED BY 'tokenizationing';" | mysql -u root
echo "CREATE DATABASE token;" | mysql -u root
echo "GRANT ALL ON token.* TO 'token';" | mysql -u root


# Import the python app, to let it create the database tables.
cd /home/synctoken/tokenserver
TOKEN_INI=/home/synctoken/tokenserver/etc/production.ini ./bin/python -c "import tokenserver.run"

# Add WIMMS records for the known nodes in this cluster.
# Actually it's just a single node...

echo "INSERT INTO token.nodes VALUES (NULL, 'sync-1.1', 'http://db1.{"Ref":"DNSPrefix"}.dev.lcip.org', 10000, 0, 10000, 0, 0);" | mysql -u root
