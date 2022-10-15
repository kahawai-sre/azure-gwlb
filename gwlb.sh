#!/bin/sh

#https://kifarunix.com/configure-ubuntu-20-04-as-linux-router/

sudo sysctl -w net.ipv4.ip_forward=1
# Update iptables as requiired. Below forwards all, but could filter.
sudo iptables -A FORWARD -j ACCEPT
sudo sysctl -p
sudo ifconfig eth0 mtu 1600
sudo ip link add vxlan${tunnel_internal_vni} type vxlan id ${tunnel_internal_vni} remote ${gwlb_lb_ip} dstport ${tunnel_internal_port} nolearning
sudo ip link set vxlan${tunnel_internal_vni} up
sudo ip route add ${public_lb_ip}/32 dev vxlan${tunnel_internal_vni} metric 100
sudo ip link add vxlan${tunnel_external_vni} type vxlan id ${tunnel_external_vni} remote ${gwlb_lb_ip} dstport ${tunnel_external_port} nolearning
sudo ip link set vxlan${tunnel_external_vni} up
# Could not get vxlan interface <=> interface routing working without bridge. ARP for chained Public LB IP was sent down external tunnel, but no response (?)
sudo ip link add br-tunnel type bridge
sudo ip link set vxlan${tunnel_internal_vni} master br-tunnel
sudo ip link set vxlan${tunnel_external_vni} master br-tunnel
sudo ip link set br-tunnel up
curl -vvv http://${public_lb_ip}
exit 0

#// Testing
# tcpdump -ni vxlan800
# ip -d link show
# ip a
# sysctl net.ipv4.ip_forward
# ifconfig vxlan${tunnel_internal_vni}
# ip -d link show vxlan${tunnel_internal_vni}
# ip -d link show vxlan${tunnel_external_vni}
# route -n
# iptables -L -v -n
# watch -n1 iptables -vnL
# watch -n1 iptables -vnl -t nat
# https://github.com/erjosito/get_nsg_logs
# python3 ./get_nsg_logs.py --account-name $storage_account_name --display-hours 2 --display-lb --display-allowed