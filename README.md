# CN IP Blocker (中国大陆IP封禁工具)

一个用于屏蔽中国大陆IP访问指定端口的简易工具。此脚本使用ipset和iptables，通过高效的哈希表方式管理大量IP地址段，实现对特定端口的访问控制。

## 功能特点

- 自动下载并应用最新的中国大陆IP段列表
- 支持针对特定端口进行封禁/解封
- 提供交互式菜单界面，操作简便
- 自动配置系统启动服务，确保重启后规则依然有效
- 提供详细的守护进程状态检查

## 一键安装

### github
```bash
wget -O cnblock.sh https://raw.githubusercontent.com/x-socks/CNipblocker/refs/heads/main/cnblock.sh && chmod +x cnblock.sh && sudo ./cnblock.sh
```


### gitlab
```bash
wget -O cnblock.sh https://gitlab.com/gitlabvps1/cnipblocker/-/raw/main/cnblock.sh && chmod +x cnblock.sh && sudo ./cnblock.sh
```


## 使用方法

### 菜单模式
直接运行脚本会显示交互式菜单：
```bash
sudo ./cnblock.sh
```

菜单选项：
1. 查看当前已封禁端口
2. 封禁端口
3. 解封端口
4. 检查服务状态(简易版)
5. 检查守护进程详细状态
6. 重新下载IP列表并更新
0. 退出

### 直接封禁端口
可以通过命令行参数直接封禁指定端口：
```bash
sudo ./cnblock.sh 80  # 封禁80端口
sudo ./cnblock.sh 443  # 封禁443端口
```

## 系统要求

- 支持iptables和ipset的Linux系统
- root权限
- 适用于大多数基于Debian的系统(如Ubuntu)和CentOS/RHEL系统

## 工作原理

脚本使用ipset创建一个包含所有中国大陆IP段的哈希表，然后通过iptables规则将特定端口的来源IP与此表进行匹配，实现高效的屏蔽操作。相比传统的直接在iptables中添加大量规则的方式，此方法大大提高了性能和可维护性。

## 注意事项

- 脚本需要root权限才能运行
- 初次运行时会自动安装所需依赖(ipset, iptables, wget)
- IP段列表基于公开数据，可能存在轻微偏差
- 系统重启后，规则会自动加载(通过systemd服务或网络启动脚本)

## 故障排除

如果遇到问题，可以使用脚本中的"检查守护进程详细状态"功能，它会提供服务状态的详细诊断信息。常见问题包括：

- IP集合未加载：检查ipset是否正确安装
- 规则未应用：检查iptables服务是否正常运行
- 守护进程未启动：检查systemd服务状态

## 使用界面

![image](https://cdn.skyimg.de/up/2025/4/21/ublqm0.webp)

## 实际效果

### 指定端口TCPing：海外可连，大陆封禁

![image](https://cdn.skyimg.net/up/2025/4/29/21480390.webp)

### 其他端口TCPing：正常

![image](https://cdn.skyimg.net/up/2025/4/29/e7298c84.webp)

### ping 正常 

![image](https://cdn.skyimg.net/up/2025/4/29/e169e6dc.webp)

## 贡献

欢迎提交问题报告和改进建议！

## 许可

MIT许可证
