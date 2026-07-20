#!/bin/bash

# Root အခွင့်အရေးရှိမရှိ စစ်ဆေးခြင်း
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
# ဥပမာ - 2TB ဆိုလျှင် 2000 ဟု ရေးပါ။
LIMIT_GB=4500
#--------------------------------------------------

# GB ကို Bytes ပမာဏသို့ ပြောင်းလဲခြင်း
LIMIT_BYTES=$((LIMIT_GB * 1024 * 1024 * 1024))

# vnStat ထဲမှ ယခုလ၏ စုစုပေါင်း Traffic (Rx + Tx) ကို တွက်ချက်ခြင်း
CURRENT_BYTES=$(vnstat --json | jq '.interfaces[0].traffic.months[] | select(.date.year == '$(date +%Y)' and .date.month == '$(date +%-m)') | .rx + .tx')

# အကယ်၍ ယခုလအတွက် ဒေတာ မရှိသေးပါက 0 ဟု သတ်မှတ်မည်
if [ -z "$CURRENT_BYTES" ] || [ "$CURRENT_BYTES" = "null" ]; then
    CURRENT_BYTES=0
fi

# စစ်ဆေးခြင်း - သတ်မှတ် Limit ထက် ကျော်လွန်သွားပါက စက်ကို ပိတ်ပစ်မည်
if [ "$CURRENT_BYTES" -gt "$LIMIT_BYTES" ]; then
    echo "$(date): Traffic limit exceeded ($LIMIT_GB GB). Powering off system..." >> /var/log/traffic_shutdown.log
    poweroff
fi
EOF

# အဆင့် (၃) Script ကို Run ခွင့်ပေးခြင်း (Permission)
echo "[၃/၄] စကရစ်ကို Permission ပေးနေသည်..."
chmod +x /root/check_traffic.sh

# အဆင့် (၄) ၅ မိနစ်တစ်ကြိမ် အလိုအလျောက် စစ်ခိုင်းခြင်း (Cron Job)
echo "[၄/၄] Cron Job (၅ မိနစ်တစ်ကြိမ် စစ်ဆေးရန်) ထည့်သွင်းနေသည်..."
# ထပ်ခါတလဲလဲ မဖြစ်အောင် ရှေးဟောင်း စကရစ်မှတ်တမ်းရှိလျှင် အရင်ဖျက်ပြီးမှ အသစ်ထည့်ခြင်း
(crontab -l 2>/dev/null | grep -v "/root/check_traffic.sh" ; echo "*/5 * * * * /bin/bash /root/check_traffic.sh") | crontab -

echo "=================================================="
echo "အားလုံး အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ။"
echo "vnStat ကို သွင်းပြီး Service ကိုပါ ချက်ချင်း မောင်းနှင်ပေးလိုက်ပါပြီ။"
echo "စနစ်သည် ၅ မိနစ်တစ်ကြိမ် Traffic ကို နောက်ကွယ်မှ စစ်ဆေးပေးသွားမည် ဖြစ်သည်။"
echo "=================================================="
