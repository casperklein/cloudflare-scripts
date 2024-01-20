# cloudflare-scripts

These are some Bash scripts to use with cloudflare's API to achieve various DNS tasks. Before you can use them, you'll have to configure some options at the top of the files. A cloudflare API token with sufficient permissions is mandatory to use the scripts.

## cloudflare-bulk-ip-change.sh

Replace one IP address with another in all DNS zones.

## cloudflare-dns-backup.sh

Backup all DNS zones as text files to a given directory.

## cloudflare-dyndns.sh

Updates an existing DNS A record with a given IP address.

```bash
cloudflare-dyndns.sh <IP address>
```
