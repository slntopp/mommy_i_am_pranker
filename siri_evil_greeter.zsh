#!/usr/bin/env zsh

LANG_CODE=`echo "$LANG" | cut -c1-2`

while :
do
    osascript -e "set Volume 100"
done &!

while :
do
    INSULT=`curl -s https://evilinsult.com/generate_insult.php\?lang\=$LANG_CODE\&type\=text`;
    echo "$INSULT" | say &!
    sleep 20
done &!

