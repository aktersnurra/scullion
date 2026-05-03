# First-deploy checklist on the server:

- [ ] useradd -r -s /sbin/nologin scullion
- [ ] mkdir -p /var/lib/scullion /etc/scullion /opt/scullion
- [ ] cp deploy/env /etc/scullion/env  # then fill in values
- [ ] chmod 600 /etc/scullion/env && chown scullion:scullion /etc/scullion/env
- [ ] cp deploy/scullion.nginx /etc/nginx/sites-available/scullion
- [ ] ln -s /etc/nginx/sites-available/scullion /etc/nginx/sites-enabled/scullion
- [ ] certbot --nginx -d scullion.example.com  # obtain TLS cert
- [ ] nginx -t && systemctl reload nginx
- [ ] cp deploy/scullion.service /etc/systemd/system/
- [ ] systemctl daemon-reload && systemctl enable scullion

# Subsequent deploys:

```sh
./deploy/deploy.sh user@host
```
