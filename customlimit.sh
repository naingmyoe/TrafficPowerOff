#!/bin/bash

# Root အခွင့်အရေးရှိမရှိ စစ်ဆေးခြင်း
if [ "$EUID" -ne 0 ]; then
  echo "ကျေးဇူးပြု၍ script ကို root သို့မဟုတ် sudo ဖြင့် run ပေးပါရန်။"
  exit 1
fi

echo "=== အလိုအလျောက် Traffic စစ်ဆေးသည့် စနစ် စတင်ထည့်သွင်းနေသည် ==="

# မြန်မာစံတော်ချိန် (Asia/Yangon) သို့ ပြောင်းလဲခြင်း
timedatectl set-timezone Asia/Yangon

# Traffic Limit ကို အသုံးပြုသူထံမှ တောင်းဆိုခြင်း
read -p "သတ်မှတ်လိုသော Traffic Limit (GB) ကို ရိုက်ထည့်ပါ [Default: 4000]: " USER_LIMIT
LIMIT_GB=${USER_LIMIT:-4000}
echo "သတ်မှတ်ထားသော Limit: ${LIMIT_GB} GB"

# အဆင့် (၁) လိုအပ်သော Packages များ သွင်းခြင်းနှင့် vnStat Service ဖွင့်ခြင်း
echo "[၁/၄] apt updates နှင့် jq, vnstat တို့ကို သွင်းနေသည်..."
apt update && apt install jq vnstat -y

echo "[၁.၅/၄] vnStat Service ကို စတင်မောင်းနှင်နေသည်..."
systemctl enable vnstat
systemctl start vnstat

# အဆင့် (၂) Auto Shutdown Script ဖန်တီးခြင်း
echo "[၂/၄] /root/check_traffic.sh စကရစ်ကို တည်ဆောက်နေသည်..."
cat << EOF > /root/check_traffic.sh
#!/bin/bash

# စနစ်လမ်းကြောင်း သတ်မှတ်ချက်
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

#--------------------------------------------------
LIMIT_GB=${LIMIT_GB}
#--------------------------------------------------

# လက်ရှိ လ အတွက် စုစုပေါင်း Traffic ကို vnstat မူလ output မှ တိုက်ရိုက်ဆွဲထုတ်ခြင်း
MONTH_STR=\$(date +%Y-%m)
LINE=\$(vnstat -i eth0 -m | grep "\$MONTH_STR")

# ရလဒ်မှ Total Value နှင့် Unit (GiB / MiB / TiB) ကို ခွဲထုတ်ခြင်း
VAL=\$(echo "\$LINE" | awk -F'|' '{print \$3}' | awk '{print \$1}')
UNIT=\$(echo "\$LINE" | awk -F'|' '{print \$3}' | awk '{print \$2}')

# Unit အလိုက် Megabytes (MB) သို့ တိကျစွာ ပြောင်းလဲတွက်ချက်ခြင်း
case "\$UNIT" in
    "TiB"|"TB")
        CURRENT_MB=\$(awk "BEGIN {printf \"%.0f\", \$VAL * 1024 * 1024}")
        ;;
    "GiB"|"GB")
        CURRENT_MB=\$(awk "BEGIN {printf \"%.0f\", \$VAL * 1024}")
        ;;
    "MiB"|"MB")
        CURRENT_MB=\$(awk "BEGIN {printf \"%.0f\", \$VAL}")
        ;;
    *)
        CURRENT_MB=0
        ;;
esac

# MB မှ GB သို့ ပြောင်းလဲခြင်း
CURRENT_GB=\$(awk "BEGIN {printf \"%.2f\", \$CURRENT_MB/1024}")
LIMIT_MB=\$((LIMIT_GB * 1024))

# ၁။ Cron run တိုင်း စစ်ဆေးချက် မှတ်တမ်းတင်ခြင်း (Date မပါဘဲ GB သာ ပြသမည်)
echo "\${CURRENT_GB} GB" > /var/log/traffic_check.log

# ၂။ စစ်ဆေးခြင်း - သတ်မှတ် Limit ထက် ကျော်လွန်သွားပါက စက်ကို ပိတ်ပစ်မည်
if [ "\$CURRENT_MB" -gt "\$LIMIT_MB" ]; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - EXCEEDED LIMIT! Current usage (\${CURRENT_GB} GB) exceeded limit (\${LIMIT_GB} GB). Powering off..." >> /var/log/traffic_shutdown.log
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
echo "စနစ်၏ Timezone ကို Myanmar Timezone (MMT) သို့ ပြောင်းလဲထားပါသည်။"
echo "လက်ရှိ သတ်မှတ်ထားသော Traffic Limit မှာ ${LIMIT_GB} GB ဖြစ်သည်။"
echo "=================================================="
