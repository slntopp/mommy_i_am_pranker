while :
do
    python3 -c "print('a' * 10000)" | say &!

    while :
    do osascript -e "set Volume 100"
    done &!

    sleep 180
done &!