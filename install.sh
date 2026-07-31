#!/bin/bash

# Root အခွင့်အရေးရှိမရှိ စစ်ဆေးခြင်းtest
if [ "$EUID" -ne 0 ]; then
  echo "ကျေးဇူးပြု၍ script ကို root သို့မဟုတ် sudo ဖြင့် run ပေးပါရန်။"
  exit 1
fi

echo "=== အလိုအလျောက် Traffic စစ်ဆေးသည့် စနစ် စတင်ထည့်သွင်းနေသည် ==="

# အဆင့် (၁) လိုအပ်သော Packages များ သွင်းခြင်းနှင့် vnStat Service ဖွင့်ခြင်း
echo "[၁/၄] apt updates နှင့် jq, vnstat တို့ကို သွင်းနေသည်..."
apt update && apt install jq vnstat -y

echo "[၁.၅/၄] vnStat Service ကို စတင်မောင်းနှင်နေသည်..."
systemctl enable vnstat
systemctl start vnstat

# အဆင့် (၂) Auto Shutdown Script ဖန်တီးခြင်း
echo "[၂/၄] /root/check_traffic.sh စကရစ်ကို တည်ဆောက်နေသည်..."
cat << 'EOF' > /root/check_traffic.sh
#!/bin/bash

# စနစ်လမ်းကြောင်း သတ်မှတ်ချက်
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

#--------------------------------------------------
# (ပြင်ဆင်ရန်) သင်သတ်မှတ်ချင်တဲ့ Traffic Limit (GB အနေနဲ့ရေးရန်)
# ဥပမာ - 4TB ဆိုလျှင် 4000 ဟု ရေးပါ။
LIMIT_GB=4000
#--------------------------------------------------

# vnStat ထဲမှ eth0 interface ၏ ယခုလအတွက် Total Traffic (Rx + Tx) ကို Megabytes (MB) အဖြစ် ဖတ်ယူခြင်း
CURRENT_MB=$(vnstat -i eth0 --json 2>/dev/null | jq '(.interfaces[]? | select(.name=="eth0") | .traffic.months[]? | select(.date.year == '$(date +%Y)' and .date.month == '$(date +%-m)') | ((.rx + .tx) / 1024 / 1024)) // 0' 2>/dev/null | awk '{print int($1)}')

# ဒေတာ မရှိသေးပါက သို့မဟုတ် null ဖြစ်ပါက 0 သတ်မှတ်မည်
if [ -z "$CURRENT_MB" ]; then
    CURRENT_MB=0
fi

# MB မှ GB သို့ ပြောင်းလဲခြင်း (Log ဖိုင်တွင် ပြသရန်အတွက်)
CURRENT_GB=$(awk "BEGIN {printf \"%.2f\", $CURRENT_MB/1024}")
LIMIT_MB=$((LIMIT_GB * 1024))

# ၁။ Cron run တိုင်း စစ်ဆေးချက် မှတ်တမ်းတင်ခြင်း (Status Log)
echo "$(date '+%Y-%m-%d %H:%M:%S') - Checked: Current usage ${CURRENT_GB} GB (${CURRENT_MB} MB) / Limit ${LIMIT_GB} GB" >> /var/log/traffic_check.log

# ၂။ စစ်ဆေးခြင်း - သတ်မှတ် Limit ထက် ကျော်လွန်သွားပါက စက်ကို ပိတ်ပစ်မည်
if [ "$CURRENT_MB" -gt "$LIMIT_MB" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - EXCEEDED LIMIT! Current usage (${CURRENT_GB} GB) exceeded limit (${LIMIT_GB} GB). Powering off..." >> /var/log/traffic_shutdown.log
    /sbin/poweroff
fi
EOF

# အဆင့် (၃) Script ကို Run ခွင့်ပေးခြင်း (Permission)
echo "[၃/၄] စကရစ်ကို Permission ပေးနေသည်..."
chmod +x /root/check_traffic.sh

# အဆင့် (၄) ၅ မိနစ်တစ်ကြိမ် အလိုအလျောက် စစ်ခိုင်းခြင်း (Cron Job)
echo "[၄/၄] Cron Job (၅ မိနစ်တစ်ကြိမ် စစ်ဆေးရန်) ထည့်သွင်းနေသည်..."
(crontab -l 2>/dev/null | grep -v "/root/check_traffic.sh" ; echo "*/5 * * * * /bin/bash /root/check_traffic.sh") | crontab -

# အဆင့် (၅) စတင်ပြီးသည်နှင့် တစ်ကြိမ် ချက်ချင်း Run ကြည့်ခြင်း
echo "စကရစ်ကို စမ်းသပ် run ကြည့်နေပါသည်..."
/bin/bash /root/check_traffic.sh

echo "=================================================="
echo "အားလုံး အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ။"
echo "စနစ်သည် ၅ မိနစ်တစ်ကြိမ် Traffic ကို နောက်ကွယ်မှ စစ်ဆေးပေးသွားမည် ဖြစ်သည်။"
echo "=================================================="
