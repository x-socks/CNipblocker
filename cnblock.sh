#!/bin/bash
# cnblock.sh - 屏蔽中国大陆IP访问指定端口的脚本
# 用法: 
#   ./cnblock.sh          - 显示交互菜单
#   ./cnblock.sh 端口号    - 直接封禁指定端口

# 检查是否有root权限
if [ "$(id -u)" -ne 0 ]; then
   echo "此脚本需要root权限" >&2
   exit 1
fi

# 检查并安装依赖
check_dependencies() {
    echo "正在检查依赖..."
    for pkg in ipset iptables wget; do
        if ! command -v $pkg &> /dev/null; then
            echo "正在安装 $pkg..."
            apt update -qq
            apt install -y $pkg
        fi
    done
}

# 下载中国IP列表
download_china_ip() {
    echo "正在下载中国IP列表..."
    wget -q -O cn.zone https://www.ipdeny.com/ipblocks/data/aggregated/cn-aggregated.zone
    if [ $? -ne 0 ] || [ ! -s cn.zone ]; then
        echo "下载中国IP列表失败，尝试备用来源..."
        wget -q -O- 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest' | \
        awk -F\| '/CN\|ipv4/ {print $4"/"32-log($5)/log(2)}' > cn.zone
    fi
}

# 创建ipset
create_ipset() {
    echo "创建IP集合..."
    ipset create china hash:net -exist
    for ip in $(cat cn.zone); do
        ipset add china $ip -exist
    done
}

# 封禁指定端口
block_port() {
    local PORT=$1
    echo "正在封禁端口 $PORT..."
    
    # 检查规则是否已存在
    iptables -C INPUT -p tcp --dport $PORT -m set --match-set china src -j DROP 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "端口 $PORT 已经被封禁"
    else
        iptables -A INPUT -p tcp --dport $PORT -m set --match-set china src -j DROP
        echo "已成功封禁端口 $PORT"
    fi
    
    # 保存规则
    save_rules
}

# 解封指定端口
unblock_port() {
    local PORT=$1
    echo "正在解封端口 $PORT..."
    
    # 尝试删除规则
    iptables -D INPUT -p tcp --dport $PORT -m set --match-set china src -j DROP 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "已成功解封端口 $PORT"
        # 保存规则
        save_rules
    else
        echo "端口 $PORT 未被封禁或解封失败"
    fi
}

# 列出已封禁端口
list_blocked_ports() {
    echo "当前已封禁的端口列表："
    BLOCKED_PORTS=$(iptables -L INPUT -n | grep 'china src' | grep 'dpt:' | sed -n 's/.*dpt:\([0-9]*\).*/\1/p')
    
    if [ -z "$BLOCKED_PORTS" ]; then
        echo "目前没有端口被封禁"
    else
        for port in $BLOCKED_PORTS; do
            echo "- 端口 $port"
        done
    fi
}

# 保存规则
save_rules() {
    echo "保存规则..."
    mkdir -p /etc/ipset
    ipset save > /etc/ipset/ipset.conf
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
}

# 配置系统服务
setup_service() {
    echo "配置自动加载服务..."
    
    # 创建网络接口启动脚本
    mkdir -p /etc/network/if-pre-up.d
    cat > /etc/network/if-pre-up.d/ipset <<'EOF'
#!/bin/bash
ipset restore < /etc/ipset/ipset.conf 2>/dev/null
iptables-restore < /etc/iptables/rules.v4 2>/dev/null
exit 0
EOF

    chmod +x /etc/network/if-pre-up.d/ipset
    
    # 对于使用systemd的系统，创建systemd服务
    if command -v systemctl &> /dev/null; then
        cat > /etc/systemd/system/ipset-restore.service <<EOF
[Unit]
Description=Restore ipset and iptables rules
Before=network-pre.target
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "ipset restore < /etc/ipset/ipset.conf"
ExecStart=/bin/bash -c "iptables-restore < /etc/iptables/rules.v4"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable ipset-restore.service
    fi
}

# 检查守护进程状态
check_daemon_status() {
    echo "============================================"
    echo "            守护进程状态检查                "
    echo "============================================"
    
    # 检查ipset集合
    echo "1. 检查中国IP集合状态:"
    if ipset list china &>/dev/null; then
        echo "   ✓ 中国IP集合已加载"
        echo "   - 当前IP数量: $(ipset list china | grep -c "^[0-9]")"
    else
        echo "   ✗ 中国IP集合未加载"
    fi
    
    # 检查iptables规则
    echo "2. 检查iptables规则状态:"
    if iptables -L | grep -q "match-set china"; then
        echo "   ✓ iptables规则已加载"
        BLOCKED_PORTS=$(iptables -L INPUT -n | grep 'china src' | grep 'dpt:' | sed -n 's/.*dpt:\([0-9]*\).*/\1/p')
        if [ -n "$BLOCKED_PORTS" ]; then
            echo "   - 已封禁端口: $BLOCKED_PORTS"
        else
            echo "   - 未发现封禁端口"
        fi
    else
        echo "   ✗ iptables规则未加载"
    fi
    
    # 检查systemd服务（如果存在）
    echo "3. 检查systemd服务状态:"
    if command -v systemctl &> /dev/null; then
        if [ -f /etc/systemd/system/ipset-restore.service ]; then
            echo "   - 服务文件检查: ✓ 存在"
            
            if systemctl is-enabled ipset-restore.service &>/dev/null; then
                echo "   - 服务启用状态: ✓ 已启用"
            else
                echo "   - 服务启用状态: ✗ 未启用"
            fi
            
            if systemctl is-active ipset-restore.service &>/dev/null; then
                echo "   - 服务运行状态: ✓ 活跃"
            else
                echo "   - 服务运行状态: ✗ 未运行"
            fi
            
            echo "   - 服务日志摘要:"
            systemctl status ipset-restore.service | grep -E "Active:|Loaded:" | sed 's/^/     /'
        else
            echo "   ✗ ipset-restore服务文件不存在"
        fi
    else
        echo "   - 系统不使用systemd"
    fi
    
    # 检查网络接口脚本
    echo "4. 检查网络接口脚本状态:"
    if [ -f /etc/network/if-pre-up.d/ipset ]; then
        echo "   ✓ 网络接口脚本存在"
        if [ -x /etc/network/if-pre-up.d/ipset ]; then
            echo "   ✓ 网络接口脚本有执行权限"
        else
            echo "   ✗ 网络接口脚本没有执行权限"
        fi
    else
        echo "   ✗ 网络接口脚本不存在"
    fi
    
    # 检查配置文件
    echo "5. 检查配置文件状态:"
    if [ -f /etc/ipset/ipset.conf ]; then
        echo "   ✓ ipset配置文件存在"
        echo "   - 上次修改时间: $(stat -c %y /etc/ipset/ipset.conf)"
    else
        echo "   ✗ ipset配置文件不存在"
    fi
    
    if [ -f /etc/iptables/rules.v4 ]; then
        echo "   ✓ iptables规则文件存在"
        echo "   - 上次修改时间: $(stat -c %y /etc/iptables/rules.v4)"
    else
        echo "   ✗ iptables规则文件不存在"
    fi
    
    echo "============================================"
}

# 检查服务状态 (简化版)
check_service_status() {
    echo "检查服务状态..."
    
    # 检查ipset集合是否存在
    if ipset list china &>/dev/null; then
        echo "✓ 中国IP集合已加载"
    else
        echo "✗ 中国IP集合未加载"
        return 1
    fi
    
    # 检查iptables规则
    if iptables -L | grep -q "match-set china"; then
        echo "✓ iptables规则已加载"
    else
        echo "✗ iptables规则未加载"
        return 1
    fi
    
    # 检查systemd服务（如果存在）
    if command -v systemctl &> /dev/null && [ -f /etc/systemd/system/ipset-restore.service ]; then
        if systemctl is-enabled ipset-restore.service &>/dev/null; then
            echo "✓ ipset-restore服务已启用"
        else
            echo "✗ ipset-restore服务未启用"
            return 1
        fi
    fi
    
    # 检查网络接口启动脚本
    if [ -x /etc/network/if-pre-up.d/ipset ]; then
        echo "✓ 网络接口启动脚本已配置"
    else
        echo "✗ 网络接口启动脚本未配置或未设置可执行权限"
        return 1
    fi
    
    return 0
}

# 完整设置流程
setup_full() {
    check_dependencies
    download_china_ip
    create_ipset
    setup_service
    save_rules
}

# 显示交互菜单
show_menu() {
    clear
    echo "============================================"
    echo "            中国大陆IP封禁工具              "
    echo "============================================"
    echo "1. 查看当前已封禁端口"
    echo "2. 封禁端口"
    echo "3. 解封端口"
    echo "4. 检查服务状态(简易版)"
    echo "5. 检查守护进程详细状态"
    echo "6. 重新下载IP列表并更新"
    echo "0. 退出"
    echo "============================================"
    echo -n "请选择操作 [0-6]: "
    read choice
    
    case $choice in
        1)
            list_blocked_ports
            ;;
        2)
            echo -n "请输入要封禁的端口号: "
            read port
            if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
                block_port $port
            else
                echo "无效的端口号"
            fi
            ;;
        3)
            echo -n "请输入要解封的端口号: "
            read port
            if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
                unblock_port $port
            else
                echo "无效的端口号"
            fi
            ;;
        4)
            check_service_status
            ;;
        5)
            check_daemon_status
            ;;
        6)
            download_china_ip
            create_ipset
            save_rules
            echo "IP列表已更新"
            ;;
        0)
            echo "退出程序"
            exit 0
            ;;
        *)
            echo "无效选择，请重新输入"
            ;;
    esac
    
    echo
    echo -n "按Enter键返回主菜单..."
    read
    show_menu
}

# 主程序入口
main() {
    # 检查ipset是否已创建，如果没有则进行完整设置
    if ! ipset list china &>/dev/null; then
        setup_full
    fi
    
    # 如果有参数，直接封禁指定端口
    if [ $# -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
        block_port $1
        check_service_status
    else
        # 否则显示交互菜单
        show_menu
    fi
}

# 运行主程序
main "$@"