#!/usr/bin/env sh

# delete some users/groups to free pid/gid
for user in ntp nobody guest; do deluser "$user" 2>/dev/null; done
for group in ntp ping nofiles users nogroup nobody; do delgroup "$group" 2>/dev/null; done

# create git user/group assigned to $PUID/$PGID
addgroup -g $PGID git
adduser -D -H -h /config -G git -u $PUID git
# enable ssh by giving a password
echo "git:*" | chpasswd -e 2>/dev/null

# run CMD or S6
if [ "$#" -gt 0 ]; then
  exec "$@"
else
  exec /init
fi
