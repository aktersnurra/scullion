# First-deploy checklist on the server:

- [ ] useradd -r -s /sbin/nologin tore
- [ ] mkdir -p /var/lib/tore /etc/tore /opt/tore
- [ ] cp deploy/env /etc/tore/env  # then fill in values
- [ ] chmod 600 /etc/tore/env && chown tore:tore /etc/tore/env
- [ ] cp deploy/tore.nginx /etc/nginx/sites-available/tore
- [ ] ln -s /etc/nginx/sites-available/tore /etc/nginx/sites-enabled/tore
- [ ] certbot --nginx -d tore.example.com  # obtain TLS cert
- [ ] nginx -t && systemctl reload nginx
- [ ] cp deploy/tore.service /etc/systemd/system/
- [ ] systemctl daemon-reload && systemctl enable tore

# Subsequent deploys:

```sh
./deploy/deploy.sh user@host
```
