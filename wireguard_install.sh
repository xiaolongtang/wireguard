#!/bin/bash

#os
if [ ! -e '/etc/redhat-release' ]; then
echo "only support centos7"
exit
fi
if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
echo "only support centos7"
exit
fi



#update os
update_kernel(){

    yum -y install epel-release curl
    sed -i "0,/enabled=0/s//enabled=1/" /etc/yum.repos.d/epel.repo
    yum remove -y kernel-devel
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
    yum --disablerepo="*" --enablerepo="elrepo-kernel" list available
    yum -y --enablerepo=elrepo-kernel install kernel-ml
    sed -i "s/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/" /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    wget https://elrepo.org/linux/kernel/el7/x86_64/RPMS/kernel-ml-devel-4.19.1-1.el7.elrepo.x86_64.rpm
    rpm -ivh kernel-ml-devel-4.19.1-1.el7.elrepo.x86_64.rpm
    yum -y --enablerepo=elrepo-kernel install kernel-ml-devel
    read -p "restart VPS，and install wireguard，do you want to restart it? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "VPS restarting..."
		reboot
	fi
}

#create random port
rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))  
}

wireguard_update(){
    yum update -y wireguard-dkms wireguard-tools
    echo "finish update"
}

wireguard_remove(){
    wg-quick down wg0
    yum remove -y wireguard-dkms wireguard-tools
    rm -rf /etc/wireguard/
    echo "finish uninstall"
}

config_client(){
cat > /etc/wireguard/client.conf <<-EOF
[Interface]
PrivateKey = $c1
Address = 10.0.0.2/24 
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $s2
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF

}

#centos7 install wireguard
wireguard_install(){
    curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
    yum install -y dkms gcc-c++ gcc-gfortran glibc-headers glibc-devel libquadmath-devel libtool systemtap systemtap-devel
    yum -y install wireguard-dkms wireguard-tools
    yum -y install qrencode
    mkdir /etc/wireguard
    cd /etc/wireguard
    wg genkey | tee sprivatekey | wg pubkey > spublickey
    wg genkey | tee cprivatekey | wg pubkey > cpublickey
    s1=$(cat sprivatekey)
    s2=$(cat spublickey)
    c1=$(cat cprivatekey)
    c2=$(cat cpublickey)
    serverip=$(curl ipv4.icanhazip.com)
    port=$(rand 10000 60000)
    eth=$(ls /sys/class/net | awk '/^e/{print}')
    chmod 777 -R /etc/wireguard
    systemctl stop firewalld
    systemctl disable firewalld
    yum install -y iptables-services 
    systemctl enable iptables 
    systemctl start iptables 
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -F
    service iptables save
    service iptables restart
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p
cat > /etc/wireguard/wg0.conf <<-EOF
[Interface]
PrivateKey = $s1
Address = 10.0.0.1/24 
PostUp   = echo 1 > /proc/sys/net/ipv4/ip_forward; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $eth -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE
ListenPort = $port
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $c2
AllowedIPs = 10.0.0.2/32
EOF

    config_client
    wg-quick up wg0
    systemctl enable wg-quick@wg0
    content=$(cat /etc/wireguard/client.conf)
    echo "use your pc download the client.conf，mobile phone scan the qr code"
    echo "${content}" | qrencode -o - -t UTF8
}
add_user(){
    echo -e "\033[37;41mcreate a user name, it cannot be the same\033[0m"
read -p "user name:" newname
    cd /etc/wireguard/
    cp client.conf $newname.conf
    wg genkey | tee temprikey | wg pubkey > tempubkey
    ipnum=$(grep Allowed /etc/wireguard/wg0.conf | tail -1 | awk -F '[ ./]' '{print $6}')
    newnum=$((10#${ipnum}+1))
    sed -i 's%^PrivateKey.*$%'"PrivateKey = $(cat temprikey)"'%' $newname.conf
    sed -i 's%^Address.*$%'"Address = 10.0.0.$newnum\/24"'%' $newname.conf

cat >> /etc/wireguard/wg0.conf <<-EOF
[Peer]
PublicKey = $(cat tempubkey)
AllowedIPs = 10.0.0.$newnum/32
EOF
    wg set wg0 peer $(cat tempubkey) allowed-ips 10.0.0.$newnum/32
echo -e "\033[37;41m added path:/etc/wireguard/$newname.conf\033[0m"
    rm -f temprikey tempubkey
}
#开始菜单
start_menu(){
    clear
    echo "========================="
    echo " for：CentOS7"
    echo " author：atrandys"
    echo " site：www.atrandys.com"
    echo " Youtube：atrandys"
    echo "========================="
    echo "1. upgrade os"
    echo "2. install wireguard"
    echo "3. upgrade wireguard"
    echo "4. uninstall wireguard"
    echo "5. show qr code"
    echo "6. add a user"
    echo "0. exit"
    echo
    read -p "type number:" num
    case "$num" in
    	1)
	update_kernel
	;;
	2)
	wireguard_install
	;;
	3)
	wireguard_update
	;;
	4)
	wireguard_remove
	;;
	5)
	content=$(cat /etc/wireguard/client.conf)
    	echo "${content}" | qrencode -o - -t UTF8
	;;
	6)
	add_user
	;;
	0)
	exit 1
	;;
	*)
	clear
	echo "type correct number"
	sleep 5s
	start_menu
	;;
    esac
}

start_menu



