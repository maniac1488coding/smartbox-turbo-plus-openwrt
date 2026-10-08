#!/bin/sh
exec ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o ConnectTimeout=8 root@192.168.1.1 "$@"
