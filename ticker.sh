#!/bin/bash
set -e

LANG=C
LC_NUMERIC=C

SYMBOLS=("$@")
THRESH=8
msg_send_thresh=3600

if ! $(type jq > /dev/null 2>&1); then
  echo "'jq' is not in the PATH. (See: https://stedolan.github.io/jq/)"
  exit 1
fi

if [ -z "$SYMBOLS" ]; then
  echo "Usage: ./ticker.sh AAPL MSFT GOOG BTC-USD"
  exit
fi


message_slack()
{
}

FIELDS=(symbol marketState regularMarketPrice regularMarketChange regularMarketChangePercent \
  preMarketPrice preMarketChange preMarketChangePercent postMarketPrice postMarketChange postMarketChangePercent)

REG="IN"
API_ENDPOINT="https://query1.finance.yahoo.com/v7/finance/quote?lang=en-US&region=$REG&corsDomain=finance.yahoo.com"

if [ -z "$NO_COLOR" ]; then
  : "${COLOR_BOLD:=\e[1;37m}"
  : "${COLOR_GREEN:=\e[32m}"
  : "${COLOR_RED:=\e[31m}"
  : "${COLOR_RESET:=\e[00m}"
fi

symbols=$(IFS=,; echo "${SYMBOLS[*]}")
fields=$(IFS=,; echo "${FIELDS[*]}")

results=$(curl --silent "$API_ENDPOINT&fields=$fields&symbols=$symbols" \
  | jq '.quoteResponse .result')

query () {
  echo $results | jq -r ".[] | select(.symbol == \"$1\") | .$2"
}

for symbol in $(IFS=' '; echo "${SYMBOLS[*]}"); do
  marketState="$(query $symbol 'marketState')"

  if [ -z $marketState ]; then
    printf 'No results for symbol "%s"\n' $symbol
    continue
  fi

  preMarketChange="$(query $symbol 'preMarketChange')"
  postMarketChange="$(query $symbol 'postMarketChange')"

  if [ $marketState == "PRE" ] \
    && [ $preMarketChange != "0" ] \
    && [ $preMarketChange != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'preMarketPrice')
    diff=$preMarketChange
    percent=$(query $symbol 'preMarketChangePercent')
  elif [ $marketState != "REGULAR" ] \
    && [ $postMarketChange != "0" ] \
    && [ $postMarketChange != "null" ]; then
    nonRegularMarketSign='*'
    price=$(query $symbol 'postMarketPrice')
    diff=$postMarketChange
    percent=$(query $symbol 'postMarketChangePercent')
  else
    nonRegularMarketSign=''
    price=$(query $symbol 'regularMarketPrice')
    diff=$(query $symbol 'regularMarketChange')
    percent=$(query $symbol 'regularMarketChangePercent')
  fi

  if [ "$diff" == "0" ]; then
    color=
  elif ( echo "$diff" | grep -q ^- ); then
    color=$COLOR_RED
  else
    color=$COLOR_GREEN
  fi

  printf "%-10s$COLOR_BOLD%8.2f$COLOR_RESET" $symbol $price
  # echo "--" $(echo "$price - $diff" | bc) "--"
  printf "$color%10.2f%12s$COLOR_RESET" $diff $(printf "(%.2f%%)" $percent)
  if [ $(bc <<< "${percent/-/} > $THRESH") -eq 1 ]
  then
        last_msg_epoch=$(cat cache.txt | jq '."'"$symbol"'"')
        last_msg_epoch=${last_msg_epoch//\"/}
        cur_epoch=$(date +%s)

        dt=$(date +%H)
        currenttime=$(date +%H:%M)
        if [[ $(($cur_epoch - $last_msg_epoch)) -gt $msg_send_thresh ]] && [[ $(dt/#0/) -lt 10 ]] && [[ "$currenttime" > "09:15" ]] && [[ "$currenttime" < "15:30" ]] && [[ $(date +%u) -lt 6 ]]
        then
            echo "sending message $symbol $cur_epoch $last_msg_epoch"
            message_slack "Movement of $symbol gth $THRESH%, it is $percent% $cur_epoch $last_msg_epoch" execution-system > /dev/null
            jq  '."'"$symbol"'" = "'"$cur_epoch"'"' cache.txt >| temp && mv temp cache.txt
        fi
  fi
  printf " %s\n" "$nonRegularMarketSign"
done
# echo '{"BANKBARODA.NS":0, "CANBK.NS":0, "HDFCBANK.NS":0, "KOTAKBANK.NS":0, "PNB.NS":0, "SBIN.NS":0}' >| cache.txt
