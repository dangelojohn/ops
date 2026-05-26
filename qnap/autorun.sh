#!/bin/sh
# QNAP user autorun — runs on every boot

# AlfaCore stack auto-start (recreate network, compose up)
(/share/CACHEDEV3_DATA/Container/odoo/scripts/boot-autostart.sh) &

# Start all Odoo + Forgejo + Caddy stacks after boot (3-min delay for Container Station to init)
( sleep 180 && /share/CACHEDEV3_DATA/Container/scripts/boot-start-stacks.sh ) &
