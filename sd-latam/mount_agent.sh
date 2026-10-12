#!/bin/bash
LOOP=$(losetup -f)
losetup -P "$LOOP" agent.img
PART="${LOOP}p1"
mkdir -p /tmp/agent_mnt
mount "$PART" /tmp/agent_mnt
ls -lah /tmp/agent_mnt/
umount /tmp/agent_mnt
losetup -d "$LOOP"
