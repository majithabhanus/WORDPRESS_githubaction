#!/bin/bash
              set -e

              apt update -y
              apt install apache2 mysql-server php php-mysql libapache2-mod-php wget unzip -y

              systemctl enable apache2
              systemctl start apache2
              systemctl enable mysql
              systemctl start mysql

              # MySQL setup
              mysql <<MYSQL_SCRIPT
              CREATE DATABASE wordpress;
              CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'StrongPassword123';
              GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
              FLUSH PRIVILEGES;
MYSQL_SCRIPT

              # Install WordPress
              cd /tmp
              wget https://wordpress.org/latest.zip
              unzip latest.zip
              rm -rf /var/www/html/*
              cp -r wordpress/* /var/www/html/

              chown -R www-data:www-data /var/www/html/
              chmod -R 755 /var/www/html/

              # Configure wp-config
              cd /var/www/html
              cp wp-config-sample.php wp-config.php
              sed -i "s/database_name_here/wordpress/" wp-config.php
              sed -i "s/username_here/wpuser/" wp-config.php
              sed -i "s/password_here/StrongPassword123/" wp-config.php

              systemctl restart apache2

              # ---------------- SSL SETUP ----------------
              a2enmod ssl

              openssl req -x509 -nodes -days 365 \
              -newkey rsa:2048 \
              -keyout /etc/ssl/private/apache-selfsigned.key \
              -out /etc/ssl/certs/apache-selfsigned.crt \
              -subj "/CN=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

              cat > /etc/apache2/sites-available/default-ssl.conf <<SSL_CONF
              <IfModule mod_ssl.c>
              <VirtualHost *:443>
                  DocumentRoot /var/www/html
                  SSLEngine on
                  SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
                  SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key
                  <Directory /var/www/html>
                      AllowOverride All
                  </Directory>
              </VirtualHost>
              </IfModule>
SSL_CONF

              a2ensite default-ssl

              # Force HTTPS
              sed -i '/<VirtualHost \\*:80>/a Redirect "/" "https://'"$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"'/"' /etc/apache2/sites-available/000-default.conf

              systemctl restart apache2

              # ---------------- CloudWatch Agent ----------------
              wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
              dpkg -i amazon-cloudwatch-agent.deb

              cat > /opt/aws/amazon-cloudwatch-agent/bin/config.json <<CW_CONFIG
              {
                "metrics": {
                  "namespace": "Custom/WordPress",
                  "metrics_collected": {
                    "mem": {
                      "measurement": ["mem_used_percent"],
                      "metrics_collection_interval": 60
                    },
                    "disk": {
                      "measurement": ["used_percent"],
                      "resources": ["/"],
                      "metrics_collection_interval": 60
                    }
                  }
                }
              }
CW_CONFIG

              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
              -a fetch-config -m ec2 \
              -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s
              EOF

  tags = {
    Name = "Terraform-WordPress-Full"
  }
}
