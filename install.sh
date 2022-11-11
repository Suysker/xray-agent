#!/usr/bin/env bash
# 检测区
# -------------------------------------------------------------
# 检查系统
export LANG=en_US.UTF-8

echoContent() {
	case $1 in
	# 红色
	"red")
		# shellcheck disable=SC2154
		${echoType} "\033[31m${printN}$2 \033[0m"
		;;
		# 天蓝色
	"skyBlue")
		${echoType} "\033[1;36m${printN}$2 \033[0m"
		;;
		# 绿色
	"green")
		${echoType} "\033[32m${printN}$2 \033[0m"
		;;
		# 白色
	"white")
		${echoType} "\033[37m${printN}$2 \033[0m"
		;;
	"magenta")
		${echoType} "\033[31m${printN}$2 \033[0m"
		;;
		# 黄色
	"yellow")
		${echoType} "\033[33m${printN}$2 \033[0m"
		;;
	esac
}

# 初始化全局变量
initVar() {
	installType='yum -y install'
	removeType='yum -y remove'
	upgrade="yum -y update"
	echoType='echo -e'

	# 核心支持的cpu版本
	xrayCoreCPUVendor=""
	# hysteriaCoreCPUVendor=""

	# 配置文件中的伪装域名
	domain=

	# 安装总进度
	totalProgress=1

	# xray安装是否完成安装
	coreInstallType=

	#内核地址
	ctlPath=

	# 当前的个性化安装方式 01234
	currentInstallProtocolType=

	# 前置类型
	frontingType=

	#xray-core配置文件的路径
	configPath=

	# 反代路径
	currentPath=

	# centos version
	centosVersion=

	# UUID
	currentUUID=

	# 集成更新证书逻辑不再使用单独的脚本--RenewTLS
	renewTLS=$1

	# tls安装失败后尝试的次数
	installTLSCount=

	# nginx配置文件路径
	nginxConfigPath=/etc/nginx/conf.d/

	# 是否为预览版
	prereleaseStatus=false

	# ssl类型
	sslType=

	# ssl邮箱
	sslEmail=

	# 检查天数
	sslRenewalDays=90

	# 伪装域名的泛域名
	TLSDomain=

	# 自定义端口
	customPort=
}

checkSystem() {
	if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
		mkdir -p /etc/yum.repos.d

		if [[ -f "/etc/centos-release" ]]; then
			centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

			if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
				centosVersion=8
			fi
		fi

		release="centos"
		installType='yum -y install'
		removeType='yum -y remove'
		upgrade="yum update -y --skip-broken"

	elif grep </etc/issue -q -i "debian" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "debian" && [[ -f "/proc/version" ]]; then
		release="debian"
		installType='apt -y install'
		upgrade="apt update"
		updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
		removeType='apt -y autoremove'

	elif grep </etc/issue -q -i "ubuntu" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "ubuntu" && [[ -f "/proc/version" ]]; then
		release="ubuntu"
		installType='apt -y install'
		upgrade="apt update"
		updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
		removeType='apt -y autoremove'
		if grep </etc/issue -q -i "16."; then
			release=
		fi
	fi

	if [[ -z ${release} ]]; then
		echoContent red "\n本脚本不支持此系统，请将下方日志反馈给开发者\n"
		echoContent yellow "$(cat /etc/issue)"
		echoContent yellow "$(cat /proc/version)"
		exit 0
	fi
}

# 检查CPU提供商
checkCPUVendor() {
	if [[ -n $(which uname) ]]; then
		if [[ "$(uname)" == "Linux" ]]; then
			case "$(uname -m)" in
			'amd64' | 'x86_64')
				xrayCoreCPUVendor="Xray-linux-64"
				# hysteriaCoreCPUVendor="hysteria-linux-amd64"
				;;
			'armv8' | 'aarch64')
				xrayCoreCPUVendor="Xray-linux-arm64-v8a"
				# hysteriaCoreCPUVendor="hysteria-linux-arm64"
				;;
			*)
				echo "  不支持此CPU架构--->"
				exit 1
				;;
			esac
		fi
	else
		echoContent red "  无法识别此CPU架构，默认amd64、x86_64--->"
		xrayCoreCPUVendor="Xray-linux-64"
	fi
}

# 检测xray是否完成安装
readInstallType() {
	coreInstallType=
	configPath=

	# 1.检测安装目录
	if [[ -d "/etc/xray-agent" ]]; then
		if [[ -d "/etc/xray-agent/xray" && -f "/etc/xray-agent/xray/xray" ]]; then
			# 这里检测xray-core
			if [[ -d "/etc/xray-agent/xray/conf" ]] && [[ -f "/etc/xray-agent/xray/conf/02_VLESS_TCP_inbounds.json" ]]; then
				# xray-core
				configPath=/etc/xray-agent/xray/conf/
				ctlPath=/etc/xray-agent/xray/xray
				coreInstallType=1
			fi
		fi
	fi
}

# 读取协议类型
readInstallProtocolType() {
	if [[ "${coreInstallType}" == "1" ]]; then
		currentInstallProtocolType=

		while read -r row; do
			if echo "${row}" | grep -q VLESS_TCP_inbounds; then
				currentInstallProtocolType=${currentInstallProtocolType}'0'
				frontingType=02_VLESS_TCP_inbounds
			fi
			if echo "${row}" | grep -q VLESS_WS_inbounds; then
				currentInstallProtocolType=${currentInstallProtocolType}'1'
			fi
			if echo "${row}" | grep -q trojan_gRPC_inbounds; then
				currentInstallProtocolType=${currentInstallProtocolType}'2'
			fi
			if echo "${row}" | grep -q VMess_WS_inbounds; then
				currentInstallProtocolType=${currentInstallProtocolType}'3'
			fi
			if echo "${row}" | grep -q 04_trojan_TCP_inbounds; then
				currentInstallProtocolType=${currentInstallProtocolType}'4'
			fi
			if echo "${row}" | grep -q VLESS_gRPC_inbounds; then
				currentInstallProtocolType=${currentInstallProtocolType}'5'
			fi
		done < <(find ${configPath} -name "*inbounds.json" | awk -F "[.]" '{print $1}')
	fi
}

# 读取默认自定义端口
readCustomPort() {
	if [[ "${coreInstallType}" == "1" ]]; then
		local port=
		port=$(jq -r .inbounds[0].port "${configPath}${frontingType}.json")
		if [[ "${port}" != "443" ]]; then
			customPort=${port}
		fi
	fi
}

# 检查文件目录以及path路径
readConfigHostPathUUID() {
	currentPath=
	currentDefaultPort=
	currentUUID=
	domain=
	# 读取path
	if [[ "${coreInstallType}" == "1" ]]; then
		local fallback
		fallback=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.path)' ${configPath}${frontingType}.json | head -1)

		local path
		path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}')

		if [[ $(echo "${fallback}" | jq -r .dest) == 31297 ]]; then
			currentPath=$(echo "${path}" | awk -F "[w][s]" '{print $1}')
		elif [[ $(echo "${fallback}" | jq -r .dest) == 31298 ]]; then
			currentPath=$(echo "${path}" | awk -F "[t][c][p]" '{print $1}')
		elif [[ $(echo "${fallback}" | jq -r .dest) == 31299 ]]; then
			currentPath=$(echo "${path}" | awk -F "[v][w][s]" '{print $1}')
		fi
		# 尝试读取alpn h2 Path

		if [[ -z "${currentPath}" ]]; then
			dest=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.alpn)|.dest' ${configPath}${frontingType}.json | head -1)
			if [[ "${dest}" == "31302" || "${dest}" == "31304" ]]; then

				if grep -q "trojangrpc {" <${nginxConfigPath}alone.conf; then
					currentPath=$(grep "trojangrpc {" <${nginxConfigPath}alone.conf | awk -F "[/]" '{print $2}' | awk -F "[t][r][o][j][a][n]" '{print $1}')
				elif grep -q "grpc {" <${nginxConfigPath}alone.conf; then
					currentPath=$(grep "grpc {" <${nginxConfigPath}alone.conf | head -1 | awk -F "[/]" '{print $2}' | awk -F "[g][r][p][c]" '{print $1}')
				fi
			fi
		fi

		local defaultPortFile=
		defaultPortFile=$(find ${configPath}* | grep "default")

		if [[ -n "${defaultPortFile}" ]]; then
			currentDefaultPort=$(echo "${defaultPortFile}" | awk -F [_] '{print $4}')
		else
			currentDefaultPort=$(jq -r .inbounds[0].port ${configPath}${frontingType}.json)
		fi

		domain=$(jq -r .inbounds[0].settings.clients[0].add ${configPath}${frontingType}.json)
		currentUUID=$(jq -r .inbounds[0].settings.clients[0].id ${configPath}${frontingType}.json)
	fi
}

# 检查是否安装宝塔
checkBTPanel() {
	if pgrep -f "BT-Panel"; then
		nginxConfigPath=/www/server/panel/vhost/nginx/
	fi
}

# 状态展示
showInstallStatus() {
	if [[ "${coreInstallType}" == "1" ]]; then
		if [[ -n $(pgrep -f xray/xray) ]]; then
			echoContent yellow "\n核心: Xray-core[运行中]"
		else
			echoContent yellow "\n核心: Xray-core[未运行]"
		fi

		# 读取协议类型
		readInstallProtocolType

		if [[ -n ${currentInstallProtocolType} ]]; then
			echoContent yellow "已安装协议: \c"
		fi
		
		if echo ${currentInstallProtocolType} | grep -q 0; then
			echoContent yellow "VLESS+TCP[TLS/XTLS] \c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 1; then
			echoContent yellow "VLESS+WS[TLS] \c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 2; then
			echoContent yellow "Trojan+gRPC[TLS] \c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 3; then
			echoContent yellow "VMess+WS[TLS] \c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 4; then
			echoContent yellow "Trojan+TCP[TLS] \c"
		fi

		if echo ${currentInstallProtocolType} | grep -q 5; then
			echoContent yellow "VLESS+gRPC[TLS] \c"
		fi
	fi
}

# 初始化安装目录
mkdirTools() {
	mkdir -p /etc/xray-agent/tls
	mkdir -p /etc/xray-agent/subscribe
	mkdir -p /etc/xray-agent/subscribe_tmp
	mkdir -p /etc/xray-agent/xray/conf
	mkdir -p /etc/systemd/system/
	mkdir -p /tmp/xray-agent-tls/
}

# 脚本快捷方式
aliasInstall() {

	if [[ -f "$HOME/install.sh" ]] && [[ -d "/etc/xray-agent" ]] && grep <"$HOME/install.sh" -q "作者:mack-a"; then
		mv "$HOME/install.sh" /etc/xray-agent/install.sh
		local vasmaType=
		if [[ -d "/usr/bin/" ]]; then
			if [[ ! -f "/usr/bin/vasma" ]]; then
				ln -s /etc/xray-agent/install.sh /usr/bin/vasma
				chmod 700 /usr/bin/vasma
				vasmaType=true
			fi

			rm -rf "$HOME/install.sh"
		elif [[ -d "/usr/sbin" ]]; then
			if [[ ! -f "/usr/sbin/vasma" ]]; then
				ln -s /etc/xray-agent/install.sh /usr/sbin/vasma
				chmod 700 /usr/sbin/vasma
				vasmaType=true
			fi
			rm -rf "$HOME/install.sh"
		fi
		if [[ "${vasmaType}" == "true" ]]; then
			echoContent green "快捷方式创建成功，可执行[vasma]重新打开脚本"
		fi
	fi
}

# 安装Nginx
installNginxTools() {

	if [[ "${release}" == "debian" ]]; then
		sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
		echo "deb http://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
		echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
		curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
		# gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
		sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
		sudo apt update >/dev/null 2>&1

	elif [[ "${release}" == "ubuntu" ]]; then
		sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
		echo "deb http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
		echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
		curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
		# gpg --dry-run --quiet --import --import-options import-show /tmp/nginx_signing.key
		sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
		sudo apt update >/dev/null 2>&1

	elif [[ "${release}" == "centos" ]]; then
		${installType} yum-utils >/dev/null 2>&1
		cat <<EOF >/etc/yum.repos.d/nginx.repo
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
		sudo yum-config-manager --enable nginx-mainline >/dev/null 2>&1
	fi
	${installType} nginx >/dev/null 2>&1
	systemctl daemon-reload
	systemctl enable nginx
}

# 安装工具包
installTools() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 安装工具"
	# 修复ubuntu个别系统问题
	if [[ "${release}" == "ubuntu" ]]; then
		dpkg --configure -a
	fi

	if [[ -n $(pgrep -f "apt") ]]; then
		pgrep -f apt | xargs kill -9
	fi

	echoContent green " ---> 检查、安装更新【新机器会很慢，如长时间无反应，请手动停止后重新执行】"

	${upgrade} >/etc/xray-agent/install.log 2>&1
	if grep <"/etc/xray-agent/install.log" -q "changed"; then
		${updateReleaseInfoChange} >/dev/null 2>&1
	fi

	if [[ "${release}" == "centos" ]]; then
		rm -rf /var/run/yum.pid
		${installType} epel-release >/dev/null 2>&1
	fi

	#	[[ -z `find /usr/bin /usr/sbin |grep -v grep|grep -w curl` ]]

	if ! find /usr/bin /usr/sbin | grep -q -w wget; then
		echoContent green " ---> 安装wget"
		${installType} wget >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w curl; then
		echoContent green " ---> 安装curl"
		${installType} curl >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w unzip; then
		echoContent green " ---> 安装unzip"
		${installType} unzip >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w socat; then
		echoContent green " ---> 安装socat"
		${installType} socat >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w tar; then
		echoContent green " ---> 安装tar"
		${installType} tar >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w cron; then
		echoContent green " ---> 安装crontabs"
		if [[ "${release}" == "ubuntu" ]] || [[ "${release}" == "debian" ]]; then
			${installType} cron >/dev/null 2>&1
		else
			${installType} crontabs >/dev/null 2>&1
		fi
	fi
	if ! find /usr/bin /usr/sbin | grep -q -w jq; then
		echoContent green " ---> 安装jq"
		${installType} jq >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w binutils; then
		echoContent green " ---> 安装binutils"
		${installType} binutils >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w ping6; then
		echoContent green " ---> 安装ping6"
		${installType} inetutils-ping >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w qrencode; then
		echoContent green " ---> 安装qrencode"
		${installType} qrencode >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w sudo; then
		echoContent green " ---> 安装sudo"
		${installType} sudo >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w lsb-release; then
		echoContent green " ---> 安装lsb-release"
		${installType} lsb-release >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w lsof; then
		echoContent green " ---> 安装lsof"
		${installType} lsof >/dev/null 2>&1
	fi

	if ! find /usr/bin /usr/sbin | grep -q -w dig; then
		echoContent green " ---> 安装dig"
		if echo "${installType}" | grep -q -w "apt"; then
			${installType} dnsutils >/dev/null 2>&1
		elif echo "${installType}" | grep -q -w "yum"; then
			${installType} bind-utils >/dev/null 2>&1
		fi
	fi

	# 检测nginx版本，并提供是否卸载的选项

	if ! find /usr/bin /usr/sbin | grep -q -w nginx; then
		echoContent green " ---> 安装nginx"
		installNginxTools
	else
		nginxVersion=$(nginx -v 2>&1)
		nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
		if [[ ${nginxVersion} -lt 14 ]]; then
			read -r -p "读取到当前的Nginx版本不支持gRPC，会导致安装失败，是否卸载Nginx后重新安装 ？[y/n]:" unInstallNginxStatus
			if [[ "${unInstallNginxStatus}" == "y" ]]; then
				${removeType} nginx >/dev/null 2>&1
				echoContent yellow " ---> nginx卸载完成"
				echoContent green " ---> 安装nginx"
				installNginxTools >/dev/null 2>&1
			else
				exit 0
			fi
		fi
	fi
	if ! find /usr/bin /usr/sbin | grep -q -w semanage; then
		echoContent green " ---> 安装semanage"
		${installType} bash-completion >/dev/null 2>&1

		if [[ "${centosVersion}" == "7" ]]; then
			policyCoreUtils="policycoreutils-python.x86_64"
		elif [[ "${centosVersion}" == "8" ]]; then
			policyCoreUtils="policycoreutils-python-utils-2.9-9.el8.noarch"
		fi

		if [[ -n "${policyCoreUtils}" ]]; then
			${installType} ${policyCoreUtils} >/dev/null 2>&1
		fi
		if [[ -n $(which semanage) ]]; then
			semanage port -a -t http_port_t -p tcp 31300

		fi
	fi

	if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
		echoContent green " ---> 安装acme.sh"
		curl -s https://get.acme.sh | sh >/etc/xray-agent/tls/acme.log 2>&1
		sudo "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade

		if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
			echoContent red "  acme安装失败--->"
			tail -n 100 /etc/xray-agent/tls/acme.log
			echoContent yellow "错误排查:"
			echoContent red "  1.获取Github文件失败，请等待Github恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
			echoContent red "  2.acme.sh脚本出现bug，可查看[https://github.com/acmesh-official/acme.sh] issues"
			echoContent red "  3.如纯IPv6机器，请设置NAT64,可执行下方命令"
			echoContent skyBlue "  echo -e \"nameserver 2001:67c:2b0::4\\\nnameserver 2001:67c:2b0::6\" >> /etc/resolv.conf"
			exit 0
		fi
	fi
}


# 操作Nginx
handleNginx() {

	if [[ -z $(pgrep -f "nginx") ]] && [[ "$1" == "start" ]]; then
		systemctl start nginx 2>/etc/xray-agent/nginx_error.log

		sleep 0.5

		if [[ -z $(pgrep -f nginx) ]]; then
			echoContent red " ---> Nginx启动失败"
			echoContent red " ---> 请手动尝试安装nginx后，再次执行脚本"
		else
			echoContent green " ---> Nginx启动成功"
		fi

	elif [[ -n $(pgrep -f "nginx") ]] && [[ "$1" == "stop" ]]; then
		systemctl stop nginx
		sleep 0.5
		if [[ -n $(pgrep -f "nginx") ]]; then
			pgrep -f "nginx" | xargs kill -9
		fi
		echoContent green " ---> Nginx关闭成功"
	fi
}

# 自定义端口
customPortFunction() {
	local historyCustomPortStatus=
	if [[ -n "${customPort}" ]]; then
		echo
		read -r -p "读取到上次安装时的端口，是否使用上次安装时的端口 ？[y/n]:" historyCustomPortStatus
		if [[ "${historyCustomPortStatus}" == "y" ]]; then
			echoContent yellow "\n ---> 端口: ${customPort}"
		fi
	fi

	if [[ "${historyCustomPortStatus}" == "n" || -z "${customPort}" ]]; then
		echo
		echoContent yellow "请输入自定义端口[例: 2083]，[回车]使用443"
		read -r -p "端口:" customPort
		if [[ -n "${customPort}" ]]; then
			if ((customPort >= 1 && customPort <= 65535)); then
				checkCustomPort
			else
				echoContent red " ---> 端口输入错误"
				exit
			fi
		else
			echoContent yellow "\n ---> 端口: 443"
		fi
	fi

}
# 检测端口是否占用
checkCustomPort() {
	if lsof -i "tcp:${customPort}" | grep -q LISTEN; then
		echoContent red "\n ---> ${customPort}端口被占用，请手动关闭后安装\n"
		lsof -i tcp:80 | grep LISTEN
		exit 0
	fi
}

# 读取tls证书详情
readAcmeTLS() {
	if [[ -n "${domain}" ]]; then
		TLSDomain=$(echo "${domain}" | awk -F "[.]" '{print $(NF-1)"."$NF}')
		if [[ "${TLSDomain}" == "eu.org" ]]; then
			TLSDomain=$(echo "${domain}" | awk -F "[.]" '{print $(NF-2)"."$(NF-1)"."$NF}')
		fi
	fi
}

# 初始化Nginx申请证书配置
initTLSNginxConfig() {
	handleNginx stop
	echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Nginx申请证书配置"
	if [[ -n "${domain}" ]]; then
		echo
		read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDomainStatus
		if [[ "${historyDomainStatus}" == "y" ]]; then
			echoContent yellow "\n ---> 域名: ${domain}"
		else
			echo
			echoContent yellow "请输入要配置的域名 例: www.xray-agent.com --->"
			read -r -p "域名:" domain
		fi
	else
		echo
		echoContent yellow "请输入要配置的域名 例: www.xray-agent.com --->"
		read -r -p "域名:" domain
	fi

	if [[ -z ${domain} ]]; then
		echoContent red "  域名不可为空--->"
		initTLSNginxConfig 3
	else
		TLSDomain=$(echo "${domain}" | awk -F "[.]" '{print $(NF-1)"."$NF}')

		if [[ "${TLSDomain}" == "eu.org" ]]; then
			TLSDomain=$(echo "${domain}" | awk -F "[.]" '{print $(NF-2)"."$(NF-1)"."$NF}')
		fi
		
		local port=80
		customPortFunction
		if [[ -n "${customPort}" ]]; then
			port=${customPort}
		fi
	fi

	readAcmeTLS
}

# 选择ssl安装类型
switchSSLType() {
	if [[ -z "${sslType}" ]]; then
		echoContent red "\n=============================================================="
		echoContent yellow "1.letsencrypt[默认]"
		echoContent yellow "2.zerossl"
		echoContent red "=============================================================="
		read -r -p "请选择[回车]使用默认:" selectSSLType
		case ${selectSSLType} in
		1)
			sslType="letsencrypt"
			;;
		2)
			sslType="zerossl"
			;;
		*)
			sslType="letsencrypt"
			;;
		esac
		touch /etc/xray-agent/tls
		echo "${sslType}" >/etc/xray-agent/tls/ssl_type

	fi
}

# 自定义email
customSSLEmail() {
	if echo "$1" | grep -q "validate email"; then
		read -r -p "是否重新输入邮箱地址[y/n]:" sslEmailStatus
		if [[ "${sslEmailStatus}" == "y" ]]; then
			sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
		else
			exit 0
		fi
	fi

	if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
		if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
			read -r -p "请输入邮箱地址:" sslEmail
			if echo "${sslEmail}" | grep -q "@"; then
				echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf
				echoContent green " ---> 添加成功"
			else
				echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
				customSSLEmail
			fi
		fi
	fi

}

#acme申请证书
acmeInstallSSL() {

	echoContent red " ---> 默认支持Cloudflare"
	echoContent red " ---> 其他DNS运营商使用方式详见 https://github.com/acmesh-official/acme.sh/wiki/dnsapi"
	echoContent red " ---> 请先根据文档自行添加密钥后,并输入n"
	read -r -p "是否使用默认Cloudflare ？[y/n]:" selectDNS
	#暂时只支持Cloudflare
	if [[ "${selectDNS}" != "n" ]]; then
		read -r -p "请输入Cloudflare API Token:" CF_Token
		sed '/CF_Token/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
		echo "SAVED_CF_Token='${CF_Token}'" >>/root/.acme.sh/account.conf
	fi

	if [[ "${selectSSLType}" == "2" ]]; then
		echoContent red " ---> zerossl需要注册账号"
		read -r -p "请输入ZeroSSL后台控制面板拿到的API Key:" ZeroSSL_API
		ZeroSSL_Result=$(curl -s -X POST "https://api.zerossl.com/acme/eab-credentials?access_key=${ZeroSSL_API}")
		Result="${ZeroSSL_Result}"
		eab_kid="$(echo "$Result" | jq -r .eab_kid)"
		eab_hmac_key="$(echo "$Result" | jq -r .eab_hmac_key)"
		sudo "$HOME/.acme.sh/acme.sh" --register-account  --server zerossl --eab-kid "${eab_kid}" --eab-hmac-key "${eab_hmac_key}"
	fi

	echoContent green " ---> 生成证书中"
	#暂时只支持Cloudflare
	sudo "$HOME/.acme.sh/acme.sh" --issue -d "${TLSDomain}" -d "*.${TLSDomain}" --dns dns_cf -k ec-256 --server "${sslType}" --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null

	readAcmeTLS
}

# 更新证书
renewalTLS() {

	if [[ -n $1 ]]; then
		echoContent skyBlue "\n进度  $1/1 : 更新证书"
	fi
	readAcmeTLS

	if [[ -d "$HOME/.acme.sh/${TLSDomain}_ecc" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.key" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" ]]; then
		modifyTime=

		modifyTime=$(stat "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" | sed -n '7,6p' | awk '{print $2" "$3" "$4" "$5}')

		modifyTime=$(date +%s -d "${modifyTime}")
		currentTime=$(date +%s)
		((stampDiff = currentTime - modifyTime))
		((days = stampDiff / 86400))
		((remainingDays = sslRenewalDays - days))

		tlsStatus=${remainingDays}
		if [[ ${remainingDays} -le 0 ]]; then
			tlsStatus="已过期"
		fi

		echoContent skyBlue " ---> 证书检查日期:$(date "+%F %H:%M:%S")"
		echoContent skyBlue " ---> 证书生成日期:$(date -d @"${modifyTime}" +"%F %H:%M:%S")"
		echoContent skyBlue " ---> 证书生成天数:${days}"
		echoContent skyBlue " ---> 证书剩余天数:"${tlsStatus}
		echoContent skyBlue " ---> 证书过期前最后一天自动更新，如更新失败请手动更新"

		if [[ ${remainingDays} -le 1 ]]; then
			echoContent yellow " ---> 重新生成证书"
			handleNginx stop
			sudo "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
			sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath /etc/xray-agent/tls/"${TLSDomain}.crt" --keypath /etc/xray-agent/tls/"${TLSDomain}.key" --ecc
			reloadCore
			handleNginx start
		else
			echoContent green " ---> 证书有效"
		fi
	else
		echoContent red " ---> 未安装"
	fi
}

# 安装TLS
installTLS() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"

	# 安装tls
	if [[ -f "/etc/xray-agent/tls/${TLSDomain}.crt" && -f "/etc/xray-agent/tls/${TLSDomain}.key" && -n $(cat "/etc/xray-agent/tls/${TLSDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${TLSDomain}_ecc" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.key" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" ]]; then
		echoContent green " ---> 检测到证书"
		renewalTLS

		if [[ -z $(find /etc/xray-agent/tls/ -name "${TLSDomain}.crt") ]] || [[ -z $(find /etc/xray-agent/tls/ -name "${TLSDomain}.key") ]] || [[ -z $(cat "/etc/xray-agent/tls/${TLSDomain}.crt") ]]; then
			sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath "/etc/xray-agent/tls/${TLSDomain}.crt" --keypath "/etc/xray-agent/tls/${TLSDomain}.key" --ecc >/dev/null
		else
			echoContent yellow " ---> 如未过期或者自定义证书请选择[n]\n"
			read -r -p "是否重新安装？[y/n]:" reInstallStatus
			if [[ "${reInstallStatus}" == "y" ]]; then
				rm -rf /etc/xray-agent/tls/*
				installTLS "$1"
			fi
		fi

	elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" || ! -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.key" ]]; then
		echoContent green " ---> 安装TLS证书"

		if [[ -d "$HOME/.acme.sh/${TLSDomain}_ecc" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.key" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" ]]; then
			sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath "/etc/xray-agent/tls/${TLSDomain}.crt" --keypath "/etc/xray-agent/tls/${TLSDomain}.key" --ecc >/dev/null
		else
			switchSSLType
			customSSLEmail
			acmeInstallSSL
			sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath "/etc/xray-agent/tls/${TLSDomain}.crt" --keypath "/etc/xray-agent/tls/${TLSDomain}.key" --ecc >/dev/null
		fi

		if [[ ! -f "/etc/xray-agent/tls/${TLSDomain}.crt" || ! -f "/etc/xray-agent/tls/${TLSDomain}.key" ]] || [[ -z $(cat "/etc/xray-agent/tls/${TLSDomain}.key") || -z $(cat "/etc/xray-agent/tls/${TLSDomain}.crt") ]]; then
			tail -n 10 /etc/xray-agent/tls/acme.log
			if [[ ${installTLSCount} == "1" ]]; then
				echoContent red " ---> TLS安装失败，请检查acme日志"
				exit 0
			fi

			installTLSCount=1
			echo
			echoContent yellow " ---> 重新尝试安装TLS证书"

			if tail -n 10 /etc/xray-agent/tls/acme.log | grep -q "Could not validate email address as valid"; then
				echoContent red " ---> 邮箱无法通过SSL厂商验证，请重新输入"
				echo
				customSSLEmail "validate email"
				installTLS "$1"
			else
				installTLS "$1"
			fi

		fi

		echoContent green " ---> TLS生成成功"
	else
		echoContent yellow " ---> 未安装acme.sh"
		exit 0
	fi
}

# 自定义/随机路径
randomPathFunction() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 生成随机路径"

	if [[ -n "${currentPath}" ]]; then
		echo
		read -r -p "读取到上次安装记录，是否使用上次安装时的path路径 ？[y/n]:" historyPathStatus
		echo
	fi

	if [[ "${historyPathStatus}" == "y" ]]; then
		echoContent green " ---> 使用成功\n"
	else
		echoContent yellow "请输入自定义路径[例: alone]，不需要斜杠，[回车]随机路径"
		read -r -p '路径:' currentPath

		if [[ -z "${currentPath}" ]]; then
			currentPath=$(head -n 50 /dev/urandom | sed 's/[^a-z]//g' | strings -n 4 | tr '[:upper:]' '[:lower:]' | head -1)
			currentPath=${currentPath:0:4}
		fi

	fi
	echoContent yellow "\n path:${currentPath}"
	echoContent skyBlue "\n----------------------------"
}

# 操作xray
handleXray() {
	if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
		if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
			systemctl start xray.service
		elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
			systemctl stop xray.service
		fi
	fi

	sleep 0.8

	if [[ "$1" == "start" ]]; then
		if [[ -n $(pgrep -f "xray/xray") ]]; then
			echoContent green " ---> Xray启动成功"
		else
			echoContent red "Xray启动失败"
			echoContent red "请手动执行【/etc/xray-agent/xray/xray -confdir /etc/xray-agent/xray/conf】，查看错误日志"
			exit 0
		fi
	elif [[ "$1" == "stop" ]]; then
		if [[ -z $(pgrep -f "xray/xray") ]]; then
			echoContent green " ---> Xray关闭成功"
		else
			echoContent red "xray关闭失败"
			echoContent red "请手动执行【ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9】"
			exit 0
		fi
	fi
}

# 安装xray
installXray() {
	readInstallType
	echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Xray"

	if [[ "${coreInstallType}" != "1" ]]; then

		version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -1)

		echoContent green " ---> Xray-core版本:${version}"
		if wget --help | grep -q show-progress; then
			wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
		else
			wget -c -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip" >/dev/null 2>&1
		fi

		unzip -o "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/xray-agent/xray >/dev/null
		rm -rf "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip"
		chmod 655 /etc/xray-agent/xray/xray
	else
		echoContent green " ---> Xray-core版本:$(/etc/xray-agent/xray/xray --version | awk '{print $2}' | head -1)"
		read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
		if [[ "${reInstallXrayStatus}" == "y" ]]; then
			rm -f /etc/xray-agent/xray/xray
			installXray "$1"
		fi
	fi
}

# Xray开机自启
installXrayService() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
	if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
		rm -rf /etc/systemd/system/xray.service
		touch /etc/systemd/system/xray.service
		execStart='/etc/xray-agent/xray/xray run -confdir /etc/xray-agent/xray/conf'
		cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=yes
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
		systemctl daemon-reload
		systemctl enable xray.service
		echoContent green " ---> 配置Xray开机自启成功"
	fi
}

# 初始化Xray 配置文件
initXrayConfig() {
	echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Xray配置"
	echo
	if [[ -n "${currentUUID}" ]]; then
		read -r -p "读取到上次安装记录，是否使用上次安装时的UUID ？[y/n]:" historyUUIDStatus
		if [[ "${historyUUIDStatus}" == "y" ]]; then
			echoContent green "\n ---> 使用成功"
		else
			echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
			read -r -p 'UUID:' currentUUID
		fi
	else
		echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
		read -r -p 'UUID:' currentUUID
	fi

	if [[ -z "${currentUUID}" ]]; then
		echoContent red "\n ---> uuid读取错误，重新生成"
		currentUUID=$(/etc/xray-agent/xray/xray uuid)
	fi

	echoContent yellow "\n ${currentUUID}"

	# log
	cat <<EOF >/etc/xray-agent/xray/conf/00_log.json
{
  "log": {
    "error": "/etc/xray-agent/xray/error.log",
    "loglevel": "warning"
  }
}
EOF

	cat <<EOF >/etc/xray-agent/xray/conf/10_ipv4_outbounds.json
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings":{
                "domainStrategy":"UseIPv4"
            },
            "tag":"IPv4-out"
        },
        {
            "protocol":"freedom",
            "settings":{
                "domainStrategy":"UseIPv6"
            },
            "tag":"IPv6-out"
        },
        {
            "protocol":"blackhole",
            "tag":"blackhole-out"
        }
    ]
}
EOF

	# routing
	rm -f /etc/xray-agent/xray/conf/09_routing.json

	# dns
	cat <<EOF >/etc/xray-agent/xray/conf/11_dns.json
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF

	# VLESS_TCP_TLS/XTLS
	# 回落nginx
	fallbacksList='{"dest":31296,"xver":1},{"alpn":"h2","dest":31302,"xver":0}'
	cat <<EOF >/etc/xray-agent/xray/conf/04_trojan_TCP_inbounds.json
{
"inbounds":[
	{
	  "port": 31296,
	  "listen": "127.0.0.1",
	  "protocol": "trojan",
	  "tag":"trojanTCP",
	  "settings": {
		"clients": [
		  {
			"password": "${currentUUID}",
			"email": "${domain}_${currentUUID}"
		  }
		],
		"fallbacks":[
			{"dest":"31300"}
		]
	  },
	  "streamSettings": {
		"network": "tcp",
		"security": "none",
		"tcpSettings": {
			"acceptProxyProtocol": true
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ]
	  }
	}
	]
}
EOF

	# VLESS_WS_TLS
	fallbacksList=${fallbacksList}',{"path":"/'${currentPath}'ws","dest":31297,"xver":1}'
	cat <<EOF >/etc/xray-agent/xray/conf/03_VLESS_WS_inbounds.json
{
"inbounds":[
    {
	  "port": 31297,
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSWS",
	  "settings": {
		"clients": [
		  {
			"id": "${currentUUID}",
			"email": "${domain}_${currentUUID}"
		  }
		],
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "ws",
		"security": "none",
		"wsSettings": {
		  "acceptProxyProtocol": true,
		  "path": "/${currentPath}ws"
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ]
	  }
	}
]
}
EOF

	# trojan_grpc
	cat <<EOF >/etc/xray-agent/xray/conf/04_trojan_gRPC_inbounds.json
{
"inbounds": [
    {
	  "port": 31304,
	  "listen": "127.0.0.1",
	  "protocol": "trojan",
	  "tag": "trojangRPCTCP",
	  "settings": {
		"clients": [
		  {
			"password": "${currentUUID}",
			"email": "${domain}_${currentUUID}"
		  }
		],
		"fallbacks": [
		  {
			"dest": "31300"
		  }
		]
	  },
	  "streamSettings": {
		"network": "grpc",
		"grpcSettings": {
		  "serviceName": "${currentPath}trojangrpc"
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ]
	  }
    }
]
}
EOF

	# VMess_WS
	fallbacksList=${fallbacksList}',{"path":"/'${currentPath}'vws","dest":31299,"xver":1}'
	cat <<EOF >/etc/xray-agent/xray/conf/05_VMess_WS_inbounds.json
{
"inbounds":[
    {
	  "listen": "127.0.0.1",
	  "port": 31299,
	  "protocol": "vmess",
	  "tag":"VMessWS",
	  "settings": {
		"clients": [
		  {
			"id": "${currentUUID}",
			"alterId": 0,
			"add": "${domain}",
			"email": "${domain}_${currentUUID}"
		  }
		]
	  },
	  "streamSettings": {
		"network": "ws",
		"security": "none",
		"wsSettings": {
		  "acceptProxyProtocol": true,
		  "path": "/${currentPath}vws"
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ]
	  }
    }
]
}
EOF

	#VLESS_GRCP
	cat <<EOF >/etc/xray-agent/xray/conf/06_VLESS_gRPC_inbounds.json
{
"inbounds":[
    {
	  "port": 31301,
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSGRPC",
	  "settings": {
		"clients": [
		  {
			"id": "${currentUUID}",
			"add": "${domain}",
			"email": "${domain}_${currentUUID}"
		  }
		],
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "grpc",
		"grpcSettings": {
		  "serviceName": "${currentPath}grpc"
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ]
	  }
    }
]
}
EOF

	# VLESS_TCP
	local defaultPort=443
	if [[ -n "${customPort}" ]]; then
		defaultPort=${customPort}
	fi

	cat <<EOF >/etc/xray-agent/xray/conf/02_VLESS_TCP_inbounds.json
{
"inbounds":[
{
  "port": ${defaultPort},
  "protocol": "vless",
  "tag":"VLESSTCP",
  "settings": {
    "clients": [
     {
        "id": "${currentUUID}",
        "add":"${domain}",
        "flow":"xtls-rprx-vision",
        "email": "${domain}_${currentUUID}"
      }
    ],
    "decryption": "none",
    "fallbacks": [
        ${fallbacksList}
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "tls",
    "tlsSettings": {
      "rejectUnknownSni": true,
      "minVersion": "1.2",
      "alpn": [
        "http/1.1",
        "h2"
      ],
      "certificates": [
        {
          "certificateFile": "/etc/xray-agent/tls/${TLSDomain}.crt",
          "keyFile": "/etc/xray-agent/tls/${TLSDomain}.key",
          "ocspStapling": 3600,
          "usage":"encipherment"
        }
      ]
    }
  }
}
]
}
EOF
}

# 定时任务更新tls证书
installCronTLS() {
	echoContent skyBlue "\n进度 $1/${totalProgress} : 添加定时维护证书"
	crontab -l >/etc/xray-agent/backup_crontab.cron
	local historyCrontab
	historyCrontab=$(sed '/install.sh/d;/acme.sh/d' /etc/xray-agent/backup_crontab.cron)
	echo "${historyCrontab}" >/etc/xray-agent/backup_crontab.cron
	echo "30 1 * * * /bin/bash /etc/xray-agent/install.sh RenewTLS >> /etc/xray-agent/crontab_tls.log 2>&1" >>/etc/xray-agent/backup_crontab.cron
	crontab /etc/xray-agent/backup_crontab.cron
	echoContent green "\n ---> 添加定时维护证书成功"
}

# 修改nginx重定向配置
updateRedirectNginxConf() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 配置镜像站点，默认使用kaggle官网"

	cat <<EOF >${nginxConfigPath}alone.conf
server {
	listen 80;
	server_name ${domain};
	return 302 https://${domain}:${currentDefaultPort};
}
server {
	listen 127.0.0.1:31302 http2 so_keepalive=on;
	server_name ${domain};

	client_header_timeout 1071906480m;
    keepalive_timeout 1071906480m;

	location /s/ {
    	add_header Content-Type text/plain;
    	alias /etc/xray-agent/subscribe/;
    }

    location /${currentPath}grpc {
    	if (\$content_type !~ "application/grpc") {
    		return 404;
    	}
 		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 1071906480m;
		grpc_read_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}

	location /${currentPath}trojangrpc {
		if (\$content_type !~ "application/grpc") {
            		return 404;
		}
 		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 1071906480m;
		grpc_read_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31304;
	}

	location / {
        add_header Strict-Transport-Security "max-age=15552000; preload" always;
		sub_filter www.kaggle.com ${domain};
		sub_filter_once off;
		proxy_set_header X-Real-IP \$remote_addr;
		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header Referer https://www.kaggle.com/;
		proxy_set_header Host www.kaggle.com;
		proxy_pass https://www.kaggle.com;
		proxy_set_header Accept-Encoding "";
		proxy_ssl_session_reuse off;
		proxy_ssl_name \$proxy_host;
		proxy_ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
	}
}
server {
	listen 127.0.0.1:31300;
	server_name ${domain};

	location /s/ {
		add_header Content-Type text/plain;
		alias /etc/xray-agent/subscribe/;
	}

	location / {
        add_header Strict-Transport-Security "max-age=15552000; preload" always;
		sub_filter www.kaggle.com ${domain};
		sub_filter_once off;
		proxy_set_header X-Real-IP \$remote_addr;
		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header Referer https://www.kaggle.com/;
		proxy_set_header Host www.kaggle.com;
		proxy_pass https://www.kaggle.com;
		proxy_set_header Accept-Encoding "";
		proxy_ssl_session_reuse off;
		proxy_ssl_name \$proxy_host;
		proxy_ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
	}
}
EOF
}

# 更新geoip和geosite
auto_update_geodata() {
	cat > /etc/xray-agent/auto_update_geodata.sh << EOF
#!/bin/sh
wget -O /etc/xray-agent/xray/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat && wget -O /etc/xray-agent/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && systemctl restart xray
EOF

	chmod +x /etc/xray-agent/auto_update_geodata.sh

	echoContent skyBlue "添加定时更新GeoData"
	crontab -l >/etc/xray-agent/backup_crontab.cron
	local historyCrontab
	historyCrontab=$(sed '/auto_update_geodata.sh/d' /etc/xray-agent/backup_crontab.cron)
	echo "${historyCrontab}" >/etc/xray-agent/backup_crontab.cron
	echo "30 1 * * * /bin/bash /etc/xray-agent/auto_update_geodata.sh >> /etc/xray-agent/crontab_geo.log 2>&1" >>/etc/xray-agent/backup_crontab.cron
	crontab /etc/xray-agent/backup_crontab.cron
	echoContent green "\n ---> 添加定时更新GeoData成功"

}

# 验证整个服务是否可用
checkGFWStatue() {
	readInstallType
	echoContent skyBlue "\n进度 $1/${totalProgress} : 验证服务启动状态"
	if [[ "${coreInstallType}" == "1" ]] && [[ -n $(pgrep -f xray/xray) ]]; then
		echoContent green " ---> 服务启动成功"
	else
		echoContent red " ---> 服务启动失败，请检查终端是否有日志打印"
		exit 0
	fi

}

# 通用
defaultBase64Code() {
	local type=$1
	local email=$2
	local id=$3

	port=${currentDefaultPort}

	local subAccount
	subAccount=$(echo "${email}" | awk -F "[_]" '{print $1}')_$(echo "${id}_currentHost" | md5sum | awk '{print $1}')
	if [[ "${type}" == "vlesstcp" ]]; then
		echoContent yellow " ---> 通用格式(VLESS+TCP+TLS/xtls-rprx-vision)"
		echoContent green "    vless://${id}@${domain}:${currentDefaultPort}?encryption=none&security=tls&type=tcp&host=${domain}&headerType=none&sni=${domain}&flow=xtls-rprx-vision#${email}\n"

		echoContent yellow " ---> 格式化明文(VLESS+TCP+TLS/xtls-rprx-vision)"
		echoContent green "协议类型:VLESS，地址:${domain}，端口:${currentDefaultPort}，用户ID:${id}，安全:tls，传输方式:tcp，flow:xtls-rprx-vision，账户名:${email}\n"
		cat <<EOF >>"/etc/xray-agent/subscribe_tmp/${subAccount}"
vless://${id}@${domain}:${currentDefaultPort}?encryption=none&security=tls&type=tcp&host=${domain}&headerType=none&sni=${domain}&flow=xtls-rprx-vision#${email}
EOF

	elif [[ "${type}" == "vmessws" ]]; then
		qrCodeBase64Default=$(echo -n "{\"port\":${currentDefaultPort},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${domain}\",\"type\":\"none\",\"path\":\"/${currentPath}vws\",\"net\":\"ws\",\"add\":\"${domain}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${domain}\",\"sni\":\"${domain}\"}" | base64 -w 0)
		qrCodeBase64Default="${qrCodeBase64Default// /}"

		echoContent yellow " ---> 通用json(VMess+WS+TLS)"
		echoContent green "    {\"port\":${currentDefaultPort},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${domain}\",\"type\":\"none\",\"path\":\"/${currentPath}vws\",\"net\":\"ws\",\"add\":\"${domain}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${domain}\",\"sni\":\"${domain}\"}\n"
		echoContent yellow " ---> 通用vmess(VMess+WS+TLS)链接"
		echoContent green "    vmess://${qrCodeBase64Default}\n"

		cat <<EOF >>"/etc/xray-agent/subscribe_tmp/${subAccount}"
vmess://${qrCodeBase64Default}
EOF

	elif [[ "${type}" == "vlessws" ]]; then

		echoContent yellow " ---> 通用格式(VLESS+WS+TLS)"
		echoContent green "    vless://${id}@${domain}:${currentDefaultPort}?encryption=none&security=tls&type=ws&host=${domain}&sni=${domain}&path=/${currentPath}ws#${email}\n"

		echoContent yellow " ---> 格式化明文(VLESS+WS+TLS)"
		echoContent green "    协议类型:VLESS，地址:${domain}，伪装域名/SNI:${domain}，端口:${currentDefaultPort}，用户ID:${id}，安全:tls，传输方式:ws，路径:/${currentPath}ws，账户名:${email}\n"

		cat <<EOF >>"/etc/xray-agent/subscribe_tmp/${subAccount}"
vless://${id}@${domain}:${currentDefaultPort}?encryption=none&security=tls&type=ws&host=${domain}&sni=${domain}&path=/${currentPath}ws#${email}
EOF

	elif [[ "${type}" == "vlessgrpc" ]]; then

		echoContent yellow " ---> 通用格式(VLESS+gRPC+TLS)"
		echoContent green "    vless://${id}@${domain}:${currentDefaultPort}?encryption=none&security=tls&type=grpc&host=${domain}&path=${currentPath}grpc&serviceName=${currentPath}grpc&alpn=h2&sni=${domain}#${email}\n"

		echoContent yellow " ---> 格式化明文(VLESS+gRPC+TLS)"
		echoContent green "    协议类型:VLESS，地址:${domain}，伪装域名/SNI:${domain}，端口:${currentDefaultPort}，用户ID:${id}，安全:tls，传输方式:gRPC，alpn:h2，serviceName:${currentPath}grpc，账户名:${email}\n"

		cat <<EOF >>"/etc/xray-agent/subscribe_tmp/${subAccount}"
vless://${id}@${domain}:${currentDefaultPort}?encryption=none&security=tls&type=grpc&host=${domain}&path=${currentPath}grpc&serviceName=${currentPath}grpc&alpn=h2&sni=${domain}#${email}
EOF
	elif [[ "${type}" == "trojan" ]]; then
		# URLEncode
		echoContent yellow " ---> Trojan(TLS)"
		echoContent green "    trojan://${id}@${domain}:${currentDefaultPort}?peer=${domain}&sni=${domain}&alpn=http/1.1#${domain}_Trojan\n"

		cat <<EOF >>"/etc/xray-agent/subscribe_tmp/${subAccount}"
trojan://${id}@${domain}:${currentDefaultPort}?peer=${domain}&sni=${domain}&alpn=http/1.1#${email}_Trojan
EOF
	elif [[ "${type}" == "trojangrpc" ]]; then
		# URLEncode

		echoContent yellow " ---> Trojan gRPC(TLS)"
		echoContent green "    trojan://${id}@${domain}:${currentDefaultPort}?encryption=none&peer=${domain}&security=tls&type=grpc&sni=${domain}&alpn=h2&path=${currentPath}trojangrpc&serviceName=${currentPath}trojangrpc#${email}\n"
		cat <<EOF >>"/etc/xray-agent/subscribe_tmp/${subAccount}"
trojan://${id}@${domain}:${currentDefaultPort}?encryption=none&peer=${domain}&security=tls&type=grpc&sni=${domain}&alpn=h2&path=${currentPath}trojangrpc&serviceName=${currentPath}trojangrpc#${email}
EOF
	fi

}


# 账号
showAccounts() {
	readInstallType
	readInstallProtocolType
	readConfigHostPathUUID
	echoContent skyBlue "\n进度 $1/${totalProgress} : 账号"
	local show
	# VLESS TCP
	if [[ -n "${configPath}" ]]; then
		show=1
		if echo "${currentInstallProtocolType}" | grep -q 0; then
			echoContent skyBlue "===================== VLESS TCP TLS/XTLS-VISION ======================\n"
			jq .inbounds[0].settings.clients ${configPath}${frontingType}.json | jq -c '.[]' | while read -r user; do
				local email=
				email=$(echo "${user}" | jq -r .email)
				echoContent skyBlue "\n ---> 账号:${email}"
				echo
				defaultBase64Code vlesstcp "${email}" "$(echo "${user}" | jq -r .id)"
			done
		fi

		# VLESS WS
		if echo ${currentInstallProtocolType} | grep -q 1; then
			echoContent skyBlue "\n================================ VLESS WS TLS CDN ================================\n"

			jq .inbounds[0].settings.clients ${configPath}03_VLESS_WS_inbounds.json | jq -c '.[]' | while read -r user; do
				local email=
				email=$(echo "${user}" | jq -r .email)
				echoContent skyBlue "\n ---> 账号:${email}"
				echo
				defaultBase64Code vlessws "${email}" "$(echo "${user}" | jq -r .id)"
			done
		fi

		# VMess WS
		if echo ${currentInstallProtocolType} | grep -q 3; then
			echoContent skyBlue "\n================================ VMess WS TLS CDN ================================\n"
			local path="${currentPath}vws"
			path="${currentPath}vws"
			jq .inbounds[0].settings.clients ${configPath}05_VMess_WS_inbounds.json | jq -c '.[]' | while read -r user; do
				local email=
				email=$(echo "${user}" | jq -r .email)
				echoContent skyBlue "\n ---> 账号:${email}"
				echo
				defaultBase64Code vmessws "${email}" "$(echo "${user}" | jq -r .id)"
			done
		fi

		# VLESS grpc
		if echo ${currentInstallProtocolType} | grep -q 5; then
			echoContent skyBlue "\n=============================== VLESS gRPC TLS CDN ===============================\n"
			echoContent red "\n --->gRPC处于测试阶段，可能对你使用的客户端不兼容，如不能使用请忽略"
			#			local serviceName
			#			serviceName=$(jq -r .inbounds[0].streamSettings.grpcSettings.serviceName ${configPath}06_VLESS_gRPC_inbounds.json)
			jq .inbounds[0].settings.clients ${configPath}06_VLESS_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
				local email=
				email=$(echo "${user}" | jq -r .email)
				echoContent skyBlue "\n ---> 账号:${email}"
				echo
				defaultBase64Code vlessgrpc "${email}" "$(echo "${user}" | jq -r .id)"
			done
		fi
	fi

	# trojan tcp
	if echo ${currentInstallProtocolType} | grep -q 4; then
		echoContent skyBlue "\n==================================  Trojan TLS  ==================================\n"
		jq .inbounds[0].settings.clients ${configPath}04_trojan_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
				local email=
				email=$(echo "${user}" | jq -r .email)
				echoContent skyBlue "\n ---> 账号:${email}"
				echo
				defaultBase64Code trojan "${email}" "$(echo "${user}" | jq -r .password)"
		done
	fi

	if echo ${currentInstallProtocolType} | grep -q 2; then
		echoContent skyBlue "\n================================  Trojan gRPC TLS  ================================\n"
		echoContent red "\n --->gRPC处于测试阶段，可能对你使用的客户端不兼容，如不能使用请忽略"
		#		local serviceName=
		#		serviceName=$(jq -r .inbounds[0].streamSettings.grpcSettings.serviceName ${configPath}04_trojan_gRPC_inbounds.json)
		jq .inbounds[0].settings.clients ${configPath}04_trojan_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
				local email=
				email=$(echo "${user}" | jq -r .email)
				echoContent skyBlue "\n ---> 账号:${email}"
				echo
				defaultBase64Code trojangrpc "${email}" "$(echo "${user}" | jq -r .password)"
		done
	fi

	if [[ -z ${show} ]]; then
		echoContent red " ---> 未安装"
	fi
}


# xray版本管理
xrayVersionManageMenu() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
	if [[ ! -d "/etc/xray-agent/xray/" ]]; then
		echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
		menu
		exit 0
	fi
	echoContent red "\n=============================================================="
	echoContent yellow "1.升级Xray-core"
	echoContent yellow "2.升级Xray-core 预览版"
	echoContent yellow "3.回退Xray-core"
	echoContent yellow "4.关闭Xray-core"
	echoContent yellow "5.打开Xray-core"
	echoContent yellow "6.重启Xray-core"
	echoContent red "=============================================================="
	read -r -p "请选择:" selectXrayType
	if [[ "${selectXrayType}" == "1" ]]; then
		updateXray
	elif [[ "${selectXrayType}" == "2" ]]; then

		prereleaseStatus=true
		updateXray

	elif [[ "${selectXrayType}" == "3" ]]; then
		echoContent yellow "\n1.只可以回退最近的五个版本"
		echoContent yellow "2.不保证回退后一定可以正常使用"
		echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
		echoContent skyBlue "------------------------Version-------------------------------"
		curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -5 | awk '{print ""NR""":"$0}'
		echoContent skyBlue "--------------------------------------------------------------"
		read -r -p "请输入要回退的版本:" selectXrayVersionType
		version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -5 | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
		if [[ -n "${version}" ]]; then
			updateXray "${version}"
		else
			echoContent red "\n ---> 输入有误，请重新输入"
			xrayVersionManageMenu 1
		fi
	elif [[ "${selectXrayType}" == "4" ]]; then
		handleXray stop
	elif [[ "${selectXrayType}" == "5" ]]; then
		handleXray start
	elif [[ "${selectXrayType}" == "6" ]]; then
		reloadCore
	fi

}

# 更新Xray
updateXray() {
	readInstallType
	if [[ "${coreInstallType}" != "1" ]]; then
		if [[ -n "$1" ]]; then
			version=$1
		else
			version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
		fi

		echoContent green " ---> Xray-core版本:${version}"

		if wget --help | grep -q show-progress; then
			wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
		else
			wget -c -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip" >/dev/null 2>&1
		fi

		unzip -o "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/xray-agent/xray >/dev/null
		rm -rf "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip"
		chmod 655 /etc/xray-agent/xray/xray
		handleXray stop
		handleXray start
	else
		echoContent green " ---> 当前Xray-core版本:$(/etc/xray-agent/xray/xray --version | awk '{print $2}' | head -1)"

		if [[ -n "$1" ]]; then
			version=$1
		else
			version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
		fi

		if [[ -n "$1" ]]; then
			read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
			if [[ "${rollbackXrayStatus}" == "y" ]]; then
				echoContent green " ---> 当前Xray-core版本:$(/etc/xray-agent/xray/xray --version | awk '{print $2}' | head -1)"

				handleXray stop
				rm -f /etc/xray-agent/xray/xray
				updateXray "${version}"
			else
				echoContent green " ---> 放弃回退版本"
			fi
		elif [[ "${version}" == "v$(/etc/xray-agent/xray/xray --version | awk '{print $2}' | head -1)" ]]; then
			read -r -p "当前版本与最新版相同，是否重新安装？[y/n]:" reInstallXrayStatus
			if [[ "${reInstallXrayStatus}" == "y" ]]; then
				handleXray stop
				rm -f /etc/xray-agent/xray/xray
				rm -f /etc/xray-agent/xray/xray
				updateXray
			else
				echoContent green " ---> 放弃重新安装"
			fi
		else
			read -r -p "最新版本为:${version}，是否更新？[y/n]:" installXrayStatus
			if [[ "${installXrayStatus}" == "y" ]]; then
				rm -f /etc/xray-agent/xray/xray
				updateXray
			else
				echoContent green " ---> 放弃更新"
			fi

		fi
	fi
}


# 备份恢复nginx文件
backupNginxConfig() {
	if [[ "$1" == "backup" ]]; then
		cp /etc/nginx/conf.d/alone.conf /etc/xray-agent/alone_backup.conf
		echoContent green " ---> nginx配置文件备份成功"
	fi

	if [[ "$1" == "restoreBackup" ]] && [[ -f "/etc/xray-agent/alone_backup.conf" ]]; then
		cp /etc/xray-agent/alone_backup.conf /etc/nginx/conf.d/alone.conf
		echoContent green " ---> nginx配置文件恢复备份成功"
		rm /etc/xray-agent/alone_backup.conf
	fi
}

# 更新伪装站
updateNginxBlog() {
	echoContent skyBlue "\n进度 $1/${totalProgress} : 更换伪装站点"
	echoContent red "\n=============================================================="
    if [[ -f "${nginxConfigPath}alone.conf" ]]; then
	
		read -r -p "请输入要镜像的域名,例如 www.baidu.com，无http/https:" mirrorDomain
	
		currentmirrorDomain=$(grep -m 1 "sub_filter.*${domain}" ${nginxConfigPath}alone.conf | awk '{print $2}')
		
		backupNginxConfig backup
    
    	sed -i "s/${currentmirrorDomain}/${mirrorDomain}/g" ${nginxConfigPath}alone.conf

    	handleNginx stop
		handleNginx start
		if [[ -z $(pgrep -f nginx) ]]; then
			backupNginxConfig restoreBackup
			handleNginx start
			exit 0
		fi
		echoContent green " ---> 更换伪站成功"
	else
		echoContent red " ---> 未安装"
	fi
}

# 输出firewall-cmd端口开放状态
checkFirewalldAllowPort() {
	if firewall-cmd --list-ports --permanent | grep -q "$1"; then
		echoContent green " ---> $1端口开放成功"
	else
		echoContent red " ---> $1端口开放失败"
		exit 0
	fi
}

# 输出ufw端口开放状态
checkUFWAllowPort() {
	if ufw status | grep -q "$1"; then
		echoContent green " ---> $1端口开放成功"
	else
		echoContent red " ---> $1端口开放失败"
		exit 0
	fi
}

# 开放系统防火墙端口
allowPort() {
	# 如果防火墙启动状态则添加相应的开放端口
	if systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
		local updateFirewalldStatus=
		if ! iptables -L | grep -q "$1(mack-a)"; then
			updateFirewalldStatus=true
			iptables -I INPUT -p tcp --dport "$1" -m comment --comment "allow $1(mack-a)" -j ACCEPT
		fi

		if echo "${updateFirewalldStatus}" | grep -q "true"; then
			netfilter-persistent save
		fi
	elif systemctl status ufw 2>/dev/null | grep -q "active (exited)"; then
		if ufw status | grep -q "Status: active"; then
			if ! ufw status | grep -q "$1"; then
				sudo ufw allow "$1"
				checkUFWAllowPort "$1"
			fi
		fi

	elif
		systemctl status firewalld 2>/dev/null | grep -q "active (running)"
	then
		local updateFirewalldStatus=
		if ! firewall-cmd --list-ports --permanent | grep -qw "$1/tcp"; then
			updateFirewalldStatus=true
			firewall-cmd --zone=public --add-port="$1/tcp" --permanent
			checkFirewalldAllowPort "$1"
		fi

		if echo "${updateFirewalldStatus}" | grep -q "true"; then
			firewall-cmd --reload
		fi
	fi
}

# 添加新端口
addCorePort() {
	echoContent skyBlue "\n功能 1/${totalProgress} : 添加新端口"
	echoContent red "\n=============================================================="
	echoContent yellow "# 注意事项\n"
	echoContent yellow "支持批量添加"
	echoContent yellow "不影响默认端口的使用"
	echoContent yellow "查看账号时，只会展示默认端口的账号"
	echoContent yellow "不允许有特殊字符，注意逗号的格式"
	echoContent yellow "录入示例:2053,2083,2087\n"

	echoContent yellow "1.添加端口"
	echoContent yellow "2.删除端口"
	echoContent red "=============================================================="
	read -r -p "请选择:" selectNewPortType
	if [[ "${selectNewPortType}" == "1" ]]; then
		read -r -p "请输入端口号:" newPort
		read -r -p "请输入默认的端口号，同时会更改订阅端口以及节点端口，[回车]默认443:" defaultPort

		if [[ -n "${defaultPort}" ]]; then
			rm -rf "$(find ${configPath}* | grep "default")"
		fi

		if [[ -n "${newPort}" ]]; then

			while read -r port; do
				rm -rf "$(find ${configPath}* | grep "${port}")"

				local fileName=
				if [[ -n "${defaultPort}" && "${port}" == "${defaultPort}" ]]; then
					fileName="${configPath}02_dokodemodoor_inbounds_${port}_default.json"
				else
					fileName="${configPath}02_dokodemodoor_inbounds_${port}.json"
				fi

				# 开放端口
				allowPort "${port}"

				local settingsPort=443
				if [[ -n "${customPort}" ]]; then
					settingsPort=${customPort}
				fi

				cat <<EOF >"${fileName}"
{
  "inbounds": [
	{
	  "listen": "0.0.0.0",
	  "port": ${port},
	  "protocol": "dokodemo-door",
	  "settings": {
		"address": "127.0.0.1",
		"port": ${settingsPort},
		"network": "tcp",
		"followRedirect": false
	  },
	  "tag": "dokodemo-door-newPort-${port}"
	}
  ]
}
EOF
			done < <(echo "${newPort}" | tr ',' '\n')

			echoContent green " ---> 添加成功"
			reloadCore
		fi
	elif [[ "${selectNewPortType}" == "2" ]]; then

		find ${configPath} -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print ""NR""":"$2}'
		read -r -p "请输入要删除的端口编号:" portIndex
		local dokoConfig
		dokoConfig=$(find ${configPath} -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print ""NR""":"$2}' | grep "${portIndex}:")
		if [[ -n "${dokoConfig}" ]]; then
			rm "${configPath}/$(echo "${dokoConfig}" | awk -F "[:]" '{print $2}')"
			reloadCore
		else
			echoContent yellow "\n ---> 编号输入错误，请重新选择"
			addCorePort
		fi
	fi
}


# manageUser 用户管理
manageUser() {
	echoContent skyBlue "\n进度 $1/${totalProgress} : 多用户管理"
	echoContent skyBlue "-----------------------------------------------------"
	echoContent yellow "1.添加用户"
	echoContent yellow "2.删除用户"
	echoContent skyBlue "-----------------------------------------------------"
	read -r -p "请选择:" manageUserType
	if [[ "${manageUserType}" == "1" ]]; then
		addUser
	elif [[ "${manageUserType}" == "2" ]]; then
		removeUser
	else
		echoContent red " ---> 选择错误"
	fi
}

# 添加用户
addUser() {

	echoContent yellow "添加新用户后，需要重新查看订阅"
	read -r -p "请输入要添加的用户数量:" userNum
	echo
	if [[ -z ${userNum} || ${userNum} -le 0 ]]; then
		echoContent red " ---> 输入有误，请重新输入"
		exit 0
	fi

	while [[ ${userNum} -gt 0 ]]; do
		local users=
		((userNum--)) || true
		uuid=$(${ctlPath} uuid)

		email=${domain}_${uuid}

		users="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${email}\",\"alterId\":0}"


		if echo ${currentInstallProtocolType} | grep -q 0; then
			local vlessUsers="${users//\,\"alterId\":0/}"

			local vlessTcpResult
			vlessTcpResult=$(jq -r ".inbounds[0].settings.clients += [${vlessUsers}]" ${configPath}${frontingType}.json)
			echo "${vlessTcpResult}" | jq . >${configPath}${frontingType}.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 1; then
			local vlessUsers="${users//\,\"alterId\":0/}"
			vlessUsers="${vlessUsers//\"flow\":\"xtls-rprx-vision\"\,/}"
			local vlessWsResult
			vlessWsResult=$(jq -r ".inbounds[0].settings.clients += [${vlessUsers}]" ${configPath}03_VLESS_WS_inbounds.json)
			echo "${vlessWsResult}" | jq . >${configPath}03_VLESS_WS_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 2; then
			local trojangRPCUsers="${users//\"flow\":\"xtls-rprx-vision\"\,/}"
			trojangRPCUsers="${trojangRPCUsers//\,\"alterId\":0/}"
			trojangRPCUsers=${trojangRPCUsers//"id"/"password"}

			local trojangRPCResult
			trojangRPCResult=$(jq -r ".inbounds[0].settings.clients += [${trojangRPCUsers}]" ${configPath}04_trojan_gRPC_inbounds.json)
			echo "${trojangRPCResult}" | jq . >${configPath}04_trojan_gRPC_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 3; then
			local vmessUsers="${users//\"flow\":\"xtls-rprx-vision\"\,/}"

			local vmessWsResult
			vmessWsResult=$(jq -r ".inbounds[0].settings.clients += [${vmessUsers}]" ${configPath}05_VMess_WS_inbounds.json)
			echo "${vmessWsResult}" | jq . >${configPath}05_VMess_WS_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 5; then
			local vlessGRPCUsers="${users//\"flow\":\"xtls-rprx-vision\"\,/}"
			vlessGRPCUsers="${vlessGRPCUsers//\,\"alterId\":0/}"

			local vlessGRPCResult
			vlessGRPCResult=$(jq -r ".inbounds[0].settings.clients += [${vlessGRPCUsers}]" ${configPath}06_VLESS_gRPC_inbounds.json)
			echo "${vlessGRPCResult}" | jq . >${configPath}06_VLESS_gRPC_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 4; then
			local trojanUsers="${users//\"flow\":\"xtls-rprx-vision\"\,/}"
			trojanUsers="${trojanUsers//id/password}"
			trojanUsers="${trojanUsers//\,\"alterId\":0/}"

			local trojanTCPResult
			trojanTCPResult=$(jq -r ".inbounds[0].settings.clients += [${trojanUsers}]" ${configPath}04_trojan_TCP_inbounds.json)
			echo "${trojanTCPResult}" | jq . >${configPath}04_trojan_TCP_inbounds.json
		fi
	done

	reloadCore
	echoContent green " ---> 添加完成"
	manageAccount 1
}

# 移除用户
removeUser() {

	if echo ${currentInstallProtocolType} | grep -q 0; then
		jq -r -c .inbounds[0].settings.clients[].email ${configPath}${frontingType}.json | awk '{print NR""":"$0}'
		read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
		if [[ $(jq -r '.inbounds[0].settings.clients|length' ${configPath}${frontingType}.json) -lt ${delUserIndex} ]]; then
			echoContent red " ---> 选择错误"
		else
			delUserIndex=$((delUserIndex - 1))
			local vlessTcpResult
			vlessTcpResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}'])' ${configPath}${frontingType}.json)
			echo "${vlessTcpResult}" | jq . >${configPath}${frontingType}.json
		fi
	fi
	if [[ -n "${delUserIndex}" ]]; then
		if echo ${currentInstallProtocolType} | grep -q 1; then
			local vlessWSResult
			vlessWSResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}'])' ${configPath}03_VLESS_WS_inbounds.json)
			echo "${vlessWSResult}" | jq . >${configPath}03_VLESS_WS_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 2; then
			local trojangRPCUsers
			trojangRPCUsers=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}'])' ${configPath}04_trojan_gRPC_inbounds.json)
			echo "${trojangRPCUsers}" | jq . >${configPath}04_trojan_gRPC_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 3; then
			local vmessWSResult
			vmessWSResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}'])' ${configPath}05_VMess_WS_inbounds.json)
			echo "${vmessWSResult}" | jq . >${configPath}05_VMess_WS_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 5; then
			local vlessGRPCResult
			vlessGRPCResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}'])' ${configPath}06_VLESS_gRPC_inbounds.json)
			echo "${vlessGRPCResult}" | jq . >${configPath}06_VLESS_gRPC_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 4; then
			local trojanTCPResult
			trojanTCPResult=$(jq -r 'del(.inbounds[0].settings.clients['${delUserIndex}'])' ${configPath}04_trojan_TCP_inbounds.json)
			echo "${trojanTCPResult}" | jq . >${configPath}04_trojan_TCP_inbounds.json
		fi

		reloadCore
	fi
	manageAccount 1
}
# 更新脚本
updateV2RayAgent() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 更新xray-agent脚本"
	rm -rf /etc/xray-agent/install.sh
	if wget --help | grep -q show-progress; then
		wget -c -q --show-progress -P /etc/xray-agent/ -N --no-check-certificate "https://raw.githubusercontent.com/suysker/xray-agent/master/install.sh"
	else
		wget -c -q -P /etc/xray-agent/ -N --no-check-certificate "https://raw.githubusercontent.com/suysker/xray-agent/master/install.sh"
	fi

	sudo chmod 700 /etc/xray-agent/install.sh
	local version
	version=$(grep '当前版本:v' "/etc/xray-agent/install.sh" | awk -F "[v]" '{print $2}' | tail -n +2 | head -n 1 | awk -F "[\"]" '{print $1}')

	echoContent green "\n ---> 更新完毕"
	echoContent yellow " ---> 请手动执行[vasma]打开脚本"
	echoContent green " ---> 当前版本:${version}\n"
	echoContent yellow "如更新不成功，请手动执行下面命令\n"
	echoContent skyBlue "wget -P /root -N --no-check-certificate https://raw.githubusercontent.com/suysker/xray-agent/master/install.sh && chmod 700 /root/install.sh && /root/install.sh"
	echo
	exit 0
}

# 查看、检查日志
checkLog() {
	if [[ "${coreInstallType}" != "1" ]]; then
		echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
	fi
	local logStatus=false
	if grep -q "access" ${configPath}00_log.json; then
		logStatus=true
	fi

	echoContent skyBlue "\n功能 $1/${totalProgress} : 查看日志"
	echoContent red "\n=============================================================="
	echoContent yellow "# 建议仅调试时打开access日志\n"

	if [[ "${logStatus}" == "false" ]]; then
		echoContent yellow "1.打开access日志"
	else
		echoContent yellow "1.关闭access日志"
	fi

	echoContent yellow "2.监听access日志"
	echoContent yellow "3.监听error日志"
	echoContent yellow "4.查看证书定时任务日志"
	echoContent yellow "5.查看证书安装日志"
	echoContent yellow "6.清空日志"
	echoContent red "=============================================================="

	read -r -p "请选择:" selectAccessLogType
	local configPathLog=${configPath//conf\//}

	case ${selectAccessLogType} in
	1)
		if [[ "${logStatus}" == "false" ]]; then
			cat <<EOF >${configPath}00_log.json
{
  "log": {
  	"access":"${configPathLog}access.log",
    "error": "${configPathLog}error.log",
    "loglevel": "debug"
  }
}
EOF
		elif [[ "${logStatus}" == "true" ]]; then
			cat <<EOF >${configPath}00_log.json
{
  "log": {
    "error": "${configPathLog}error.log",
    "loglevel": "warning"
  }
}
EOF
		fi
		reloadCore
		checkLog 1
		;;
	2)
		tail -f ${configPathLog}access.log
		;;
	3)
		tail -f ${configPathLog}error.log
		;;
	4)
		tail -n 100 /etc/xray-agent/crontab_tls.log
		;;
	5)
		tail -n 100 /etc/xray-agent/tls/acme.log
		;;
	6)
		echo >${configPathLog}access.log
		echo >${configPathLog}error.log
		;;
	esac
}

warpRouting() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : WARP分流"
	echoContent red "=============================================================="
	if [[ -z $(which warp-cli) ]]; then
		echoContent red " ---> 安装WARP未安装"
		echoContent red " ---> 请运行脚本并安装"
		exit 0
	fi
	echoContent red "\n=============================================================="
	echoContent yellow "1.添加域名"
	echoContent yellow "2.卸载WARP分流"
	echoContent yellow "3.分流CN"
	echoContent yellow "4.卸载分流CN"
	echoContent red "=============================================================="
	read -r -p "请选择:" warpStatus
	if [[ "${warpStatus}" != "2" && "${warpStatus}" != "4" ]]; then
		echoContent red "\n=============================================================="
		echoContent yellow "# 注意事项\n"
		echoContent yellow "1.如果安装时选择添加WARP IPv4、IPv6或者双栈接口，则所有流量均通过WARP（分流可能无意义）"
		echoContent yellow "2.规则仅支持预定义域名列表[https://github.com/v2fly/domain-list-community]"
		echoContent yellow "3.只可以把流量分流给warp，不可指定是ipv4或者ipv6"
	
		if [[ -n $(ip address show  wgcf) ]]; then
			echoContent yellow "\n=============================================================="
			choContent yellow "目前所有流量均通过WARP（分流可能无意义）"
			warp_ip=$(ifconfig  wgcf | head -n2 | grep inet | awk '{print$2}')
		fi

		if [[ -n $(ip address show  CloudflareWARP) ]]; then
			echoContent yellow "\n=============================================================="
			echoContent yellow "目前为WARP Client模式，可以正常分流"
			warp_ip=$(ifconfig  CloudflareWARP | head -n2 | grep inet | awk '{print$2}')
		fi

		local outbounds
		
		if [[ -n ${warp_ip} ]]; then
			if [[ "${warpStatus}" == "1" ]]; then
				unInstallOutbounds warp-out
				outbounds=$(jq -r ".outbounds += [{\"protocol\":\"freedom\",\"settings\":{\"domainStrategy\":\"AsIs\"},\"sendThrough\":\"${warp_ip}\",\"tag\":\"warp-out\"}]" ${configPath}10_ipv4_outbounds.json)
			elif [[ "${warpStatus}" == "3" ]]; then
				unInstallOutbounds warp-out-cn
				outbounds=$(jq -r ".outbounds += [{\"protocol\":\"freedom\",\"settings\":{\"domainStrategy\":\"AsIs\"},\"sendThrough\":\"${warp_ip}\",\"tag\":\"warp-out-cn\"}]" ${configPath}10_ipv4_outbounds.json)
			fi
		else
			echoContent yellow "检测到可能安装 WARP Linux Client，开启了 Socks5 代理模式"
			echoContent yellow "请输入监听端口，脚本默认为40000"
			warp_port=40000
			read -r -p "请输入WARP Socks5 代理监听端口:" warp_port
			if [[ "${warpStatus}" == "1" ]]; then
				unInstallOutbounds warp-out
				outbounds=$(jq -r ".outbounds += [{\"protocol\":\"socks\",\settings\":{\"servers\":[{\"address\":\"127.0.0.1\",\"port\":\"${warp_port}\"}]},\"tag\":\"warp-out\"}]" ${configPath}10_ipv4_outbounds.json)
			elif [[ "${warpStatus}" == "3" ]]; then
				unInstallOutbounds warp-out-cn
				outbounds=$(jq -r ".outbounds += [{\"protocol\":\"socks\",\settings\":{\"servers\":[{\"address\":\"127.0.0.1\",\"port\":\"${warp_port}\"}]},\"tag\":\"warp-out-cn\"}]" ${configPath}10_ipv4_outbounds.json)
			fi
		fi
		echo "${outbounds}" | jq . >${configPath}10_ipv4_outbounds.json

		if [[ "${warpStatus}" == "1" ]]; then
			echoContent yellow "4.如内核启动失败请检查域名后重新添加域名"
			echoContent yellow "5.不允许有特殊字符，注意逗号的格式"
			echoContent yellow "6.每次添加都是重新添加，不会保留上次域名"
			echoContent yellow "7.录入示例:google,youtube,facebook\n"
			read -r -p "请按照上面示例录入域名:" domainList
	
			if [[ -f "${configPath}09_routing.json" ]]; then
				unInstallRouting warp-out outboundTag

				routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"domain\":[\"geosite:${domainList//,/\",\"geosite:}\"],\"outboundTag\":\"warp-out\"}]" ${configPath}09_routing.json)

				echo "${routing}" | jq . >${configPath}09_routing.json

			else
				cat <<EOF >${configPath}09_routing.json
{
    "routing":{
        "domainStrategy": "IPOnDemand",
        "rules": [
          {
            "type": "field",
            "domain": [
            	"geosite:${domainList//,/\",\"geosite:}"
            ],
            "outboundTag": "warp-out"
          }
        ]
  }
}
EOF
			fi
		elif [[ "${warpStatus}" == "3" ]]; then
			if [[ -f "${configPath}09_routing.json" ]]; then
				unInstallRouting warp-out-cn outboundTag
				routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"ip\":[\"geoip:cn\"],\"outboundTag\":\"warp-out-cn\"}]" ${configPath}09_routing.json)

				echo "${routing}" | jq . >${configPath}09_routing.json
			else
				cat <<EOF >"${configPath}09_routing.json"
{
    "routing":{
        "domainStrategy": "IPOnDemand",
        "rules": [
          {
            "type": "field",
            "ip": [
            	"geoip:cn"
            ],
            "outboundTag": "warp-out-cn"
          }
        ]
  }
}
EOF
			fi
			unInstallRouting blackhole-out outboundTag
		else
			echoContent red " ---> 选择错误"
			exit 0
		fi

		echoContent green " ---> 添加成功"

	elif [[ "${warpStatus}" == "2" ]]; then

		unInstallRouting warp-out outboundTag

		unInstallOutbounds warp-out

		echoContent green " ---> WARP分流卸载成功"
	elif [[ "${warpStatus}" == "4" ]]; then

		unInstallRouting warp-out-cn outboundTag

		unInstallOutbounds warp-out-cn

		echoContent green " ---> 分流CN卸载成功"
	else
		echoContent red " ---> 选择错误"
		exit 0
	fi
	reloadCore

}

# 阻止访问中国大陆IP
BlockCNIP() {
	if [[ "${coreInstallType}" != "1" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi
	echoContent skyBlue "\n功能 1/${totalProgress} : 阻止访问中国大陆IP"
	echoContent yellow "若不想阻止访问CN的IP，请使用warp分流功能"
	echoContent red "\n=============================================================="
	echoContent yellow "1.启用"
	echoContent yellow "2.卸载"
	echoContent red "=============================================================="
	read -r -p "请选择:" CNIPStatus
	if [[ "${CNIPStatus}" == "1" ]]; then
		if [[ -f "${configPath}09_routing.json" ]]; then
			unInstallRouting blackhole-out outboundTag
			routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"ip\":[\"geoip:cn\"],\"outboundTag\":\"blackhole-out\"}]" ${configPath}09_routing.json)

			echo "${routing}" | jq . >${configPath}09_routing.json
		else
			cat <<EOF >"${configPath}09_routing.json"
{
    "routing":{
        "domainStrategy": "IPOnDemand",
        "rules": [
          {
            "type": "field",
            "ip": [
            	"geoip:cn"
            ],
            "outboundTag": "blackhole-out"
          }
        ]
  }
}
EOF
		fi

		unInstallOutbounds blackhole-out

		outbounds=$(jq -r '.outbounds += [{"protocol":"blackhole","tag":"blackhole-out"}]' ${configPath}10_ipv4_outbounds.json)

		echo "${outbounds}" | jq . >${configPath}10_ipv4_outbounds.json

		unInstallRouting warp-out-cn outboundTag

		unInstallOutbounds warp-out-cn

		echoContent green " ---> 添加成功"
	else
		unInstallRouting blackhole-out outboundTag
		echoContent green " ---> 阻止访问中国大陆IP卸载成功"
	fi
	reloadCore
}

# 检查ipv6、ipv4
checkIPv6() {
	# pingIPv6=$(ping6 -c 1 www.google.com | sed '2{s/[^(]*(//;s/).*//;q;}' | tail -n +2)
	pingIPv6=$(ping6 -c 1 www.google.com | sed -n '1p' | sed 's/.*(//g;s/).*//g')

	if [[ -z "${pingIPv6}" ]]; then
		echoContent red " ---> 不支持ipv6"
		exit 0
	fi
}

# ipv6 分流
ipv6Routing() {
	if [[ "${coreInstallType}" != "1" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi

	checkIPv6
	echoContent skyBlue "\n功能 1/${totalProgress} : IPv6分流"
	echoContent red "\n=============================================================="
	echoContent yellow "1.添加域名"
	echoContent yellow "2.卸载IPv6分流"
	echoContent yellow "3.全局IPv6优先"
	echoContent yellow "4.全局IPv4优先"
	echoContent red "=============================================================="
	read -r -p "请选择:" ipv6Status
	if [[ "${ipv6Status}" == "1" ]]; then
		echoContent red "=============================================================="
		echoContent yellow "# 注意事项\n"
		echoContent yellow "1.规则仅支持预定义域名列表[https://github.com/v2fly/domain-list-community]"
		echoContent yellow "2.详细文档[https://www.v2fly.org/config/routing.html]"
		echoContent yellow "3.如内核启动失败请检查域名后重新添加域名"
		echoContent yellow "4.不允许有特殊字符，注意逗号的格式"
		echoContent yellow "5.每次添加都是重新添加，不会保留上次域名"
		echoContent yellow "6.强烈建议屏蔽国内的网站，下方输入【cn】即可屏蔽"
		echoContent yellow "7.录入示例:google,youtube,facebook,cn\n"
		read -r -p "请按照上面示例录入域名:" domainList

		if [[ -f "${configPath}09_routing.json" ]]; then

			unInstallRouting IPv6-out outboundTag

			routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"domain\":[\"geosite:${domainList//,/\",\"geosite:}\"],\"outboundTag\":\"IPv6-out\"}]" ${configPath}09_routing.json)

			echo "${routing}" | jq . >${configPath}09_routing.json

		else
			cat <<EOF >"${configPath}09_routing.json"
{
    "routing":{
        "domainStrategy": "IPOnDemand",
        "rules": [
          {
            "type": "field",
            "domain": [
            	"geosite:${domainList//,/\",\"geosite:}"
            ],
            "outboundTag": "IPv6-out"
          }
        ]
  }
}
EOF
		fi

		unInstallOutbounds IPv4-out
		unInstallOutbounds IPv6-out
		unInstallOutbounds blackhole-out

		outbounds=$(jq -r '.outbounds = [{"protocol":"freedom","settings":{"domainStrategy":"UseIPv4"},"tag":"IPv4-out"},{"protocol":"freedom","settings":{"domainStrategy":"UseIPv6"},"tag":"IPv6-out"}] + .outbounds + [{"protocol":"blackhole","tag":"blackhole-out"}]' ${configPath}10_ipv4_outbounds.json)

		echo "${outbounds}" | jq . >${configPath}10_ipv4_outbounds.json

		echoContent green " ---> 添加成功"

	elif [[ "${ipv6Status}" == "2" ]]; then

		unInstallRouting IPv6-out outboundTag

		echoContent green " ---> IPv6分流卸载成功"
    elif [[ "${ipv6Status}" == "3" ]]; then

			unInstallOutbounds IPv4-out
			unInstallOutbounds IPv6-out
			unInstallOutbounds blackhole-out

			outbounds=$(jq -r '.outbounds = [{"protocol":"freedom","settings":{"domainStrategy":"UseIPv6"},"tag":"IPv6-out"},{"protocol":"freedom","settings":{"domainStrategy":"UseIPv4"},"tag":"IPv4-out"}] + .outbounds + [{"protocol":"blackhole","tag":"blackhole-out"}]' ${configPath}10_ipv4_outbounds.json)

			echo "${outbounds}" | jq . >${configPath}10_ipv4_outbounds.json
        
		echoContent green " ---> 全局IPv6优先"
       
    elif [[ "${ipv6Status}" == "4" ]]; then

			unInstallOutbounds IPv4-out
			unInstallOutbounds IPv6-out
			unInstallOutbounds blackhole-out

			outbounds=$(jq -r '.outbounds = [{"protocol":"freedom","settings":{"domainStrategy":"UseIPv4"},"tag":"IPv4-out"},{"protocol":"freedom","settings":{"domainStrategy":"UseIPv6"},"tag":"IPv6-out"}] + .outbounds + [{"protocol":"blackhole","tag":"blackhole-out"}]' ${configPath}10_ipv4_outbounds.json)

			echo "${outbounds}" | jq . >${configPath}10_ipv4_outbounds.json
		
        echoContent green " ---> 全局IPv4优先，不影响IPV6分流"

	else
		echoContent red " ---> 选择错误"
		exit 0
	fi

	reloadCore
}

# 根据tag卸载Routing
unInstallRouting() {
	local tag=$1
	local type=$2
	local protocol=$3

	if [[ -f "${configPath}09_routing.json" ]]; then
		local routing
		if grep -q "${tag}" ${configPath}09_routing.json && grep -q "${type}" ${configPath}09_routing.json; then

			jq -c .routing.rules[] ${configPath}09_routing.json | while read -r line; do
				local index=$((index + 1))
				local delStatus=0
				if [[ "${type}" == "outboundTag" ]] && echo "${line}" | jq .outboundTag | grep -q "${tag}"; then
					delStatus=1
				elif [[ "${type}" == "inboundTag" ]] && echo "${line}" | jq .inboundTag | grep -q "${tag}"; then
					delStatus=1
				fi

				if [[ -n ${protocol} ]] && echo "${line}" | jq .protocol | grep -q "${protocol}"; then
					delStatus=1
				elif [[ -z ${protocol} ]] && [[ $(echo "${line}" | jq .protocol) != "null" ]]; then
					delStatus=0
				fi

				if [[ ${delStatus} == 1 ]]; then
					routing=$(jq -r 'del(.routing.rules['"$(("${index}" - 1))"'])' ${configPath}09_routing.json)
					echo "${routing}" | jq . >${configPath}09_routing.json
				fi
			done
		fi
	fi
}

# 根据tag卸载出站
unInstallOutbounds() {
	local tag=$1

	if grep -q "${tag}" ${configPath}10_ipv4_outbounds.json; then
		local ipv6OutIndex
		ipv6OutIndex=$(jq .outbounds[].tag ${configPath}10_ipv4_outbounds.json | awk '{print ""NR""":"$0}' | grep "${tag}" | awk -F "[:]" '{print $1}' | head -1)
		if [[ ${ipv6OutIndex} -gt 0 ]]; then
			routing=$(jq -r 'del(.outbounds['$(("${ipv6OutIndex}" - 1))'])' ${configPath}10_ipv4_outbounds.json)
			echo "${routing}" | jq . >${configPath}10_ipv4_outbounds.json
		fi
	fi

}

# 重启核心
reloadCore() {
	handleXray stop
	handleXray start
}


# xray-core 安装
xrayCoreInstall() {
	totalProgress=11
	installTools 1
	# 申请tls
	initTLSNginxConfig 2

	handleXray stop

	installTLS 3
	handleNginx stop
	randomPathFunction 4
	# 安装Xray
	installXray 5
	installXrayService 6
	initXrayConfig 7
	installCronTLS 8
	updateRedirectNginxConf 9
	handleXray stop
	sleep 2
	handleXray start

	handleNginx start
	auto_update_geodata
	# 生成账号
	checkGFWStatue 10
	showAccounts 11
}

# 定时任务检查证书
cronRenewTLS() {
	if [[ "${renewTLS}" == "RenewTLS" ]]; then
		renewalTLS
		exit 0
	fi
}
# 账号管理
manageAccount() {
	echoContent skyBlue "\n功能 1/${totalProgress} : 账号管理"
	echoContent red "\n=============================================================="
	echoContent yellow "# 每次删除、添加账号后，需要重新查看订阅生成订阅\n"
	echoContent yellow "1.查看账号"
	echoContent yellow "2.查看订阅"
	echoContent yellow "3.添加用户"
	echoContent yellow "4.删除用户"
	echoContent red "=============================================================="
	read -r -p "请输入:" manageAccountStatus
	if [[ "${manageAccountStatus}" == "1" ]]; then
		showAccounts 1
	elif [[ "${manageAccountStatus}" == "2" ]]; then
		subscribe 1
	elif [[ "${manageAccountStatus}" == "3" ]]; then
		addUser
	elif [[ "${manageAccountStatus}" == "4" ]]; then
		removeUser
	else
		echoContent red " ---> 选择错误"
	fi
}

# 订阅
subscribe() {
	if [[ "${coreInstallType}" == "1" ]]; then
		echoContent skyBlue "-------------------------备注---------------------------------"
		echoContent yellow "# 查看订阅时会重新生成订阅"
		echoContent yellow "# 每次添加、删除账号需要重新查看订阅"
		rm -rf /etc/xray-agent/subscribe/*
		rm -rf /etc/xray-agent/subscribe_tmp/*
		showAccounts >/dev/null
		mv /etc/xray-agent/subscribe_tmp/* /etc/xray-agent/subscribe/

		if [[ -n $(ls /etc/xray-agent/subscribe/) ]]; then
			find /etc/xray-agent/subscribe/* | while read -r email; do
				email=$(echo "${email}" | awk -F "[b][e][/]" '{print $2}')

				local base64Result
				base64Result=$(base64 -w 0 "/etc/xray-agent/subscribe/${email}")
				echo "${base64Result}" >"/etc/xray-agent/subscribe/${email}"
				echoContent skyBlue "--------------------------------------------------------------"
				echoContent yellow "email:${email}\n"
				local currentDomain=${domain}

				if [[ -n "${currentDefaultPort}" && "${currentDefaultPort}" != "443" ]]; then
					currentDomain="${domain}:${currentDefaultPort}"
				fi

				echoContent yellow "url:https://${currentDomain}/s/${email}\n"
				echo "https://${currentDomain}/s/${email}" | qrencode -s 10 -m 1 -t UTF8
				echoContent skyBlue "--------------------------------------------------------------"
			done
		fi
	else
		echoContent red " ---> 未安装"
	fi
}

# 卸载脚本
unInstall() {
	read -r -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
	if [[ "${unInstallStatus}" != "y" ]]; then
		echoContent green " ---> 放弃卸载"
		menu
		exit 0
	fi

	handleNginx stop
	if [[ -z $(pgrep -f "nginx") ]]; then
		echoContent green " ---> 停止Nginx成功"
	fi

	if [[ "${coreInstallType}" == "1" ]]; then
		handleXray stop
		rm -rf /etc/systemd/system/xray.service
		echoContent green " ---> 删除Xray开机自启完成"
	fi

	if [[ -f "/root/.acme.sh/acme.sh.env" ]] && grep -q 'acme.sh.env' </root/.bashrc; then
		sed -i 's/. "\/root\/.acme.sh\/acme.sh.env"//g' "$(grep '. "/root/.acme.sh/acme.sh.env"' -rl /root/.bashrc)"
	fi
	rm -rf /root/.acme.sh
	echoContent green " ---> 删除acme.sh完成"

	rm -rf /tmp/xray-agent-tls/*
	if [[ -d "/etc/xray-agent/tls" ]] && [[ -n $(find /etc/xray-agent/tls/ -name "*.key") ]] && [[ -n $(find /etc/xray-agent/tls/ -name "*.crt") ]]; then
		mv /etc/xray-agent/tls /tmp/xray-agent-tls
		if [[ -n $(find /tmp/xray-agent-tls -name '*.key') ]]; then
			echoContent yellow " ---> 备份证书成功，请注意留存。[/tmp/xray-agent-tls]"
		fi
	fi

	rm -rf /etc/xray-agent
	rm -rf ${nginxConfigPath}alone.conf

	if [[ -d "/usr/share/nginx/html" && -f "/usr/share/nginx/html/check" ]]; then
		rm -rf /usr/share/nginx/html
		echoContent green " ---> 删除伪装网站完成"
	fi

	rm -rf /usr/bin/vasma
	rm -rf /usr/sbin/vasma
	echoContent green " ---> 卸载快捷方式完成"
	echoContent green " ---> 卸载xray-agent脚本完成"
}

# Adguardhome管理
AdguardManageMenu() {
	echoContent skyBlue "\nAdguardhome管理"
	echoContent red "\n=============================================================="
	echoContent yellow "1.安装Adguardhome"
	echoContent yellow "2.升级Adguardhome"
	echoContent yellow "3.卸载Adguardhome"
	echoContent yellow "4.关闭Adguardhome"
	echoContent yellow "5.打开Adguardhome"
	echoContent yellow "6.重启Adguardhome"
	echoContent red "=============================================================="
	read -r -p "请选择:" selectADGType
	if [[ "${selectADGType}" == "1" ]]; then
		if [[ -d "/opt/AdGuardHome/" ]]; then
			echoContent red " ---> 检测到安装目录，请执行脚本卸载内容"
			menu
			exit 0
		fi
		#官方的安装脚本
		curl -sSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh
		#解除53端口占用
		systemctl stop systemd-resolved
		systemctl disable systemd-resolved
	fi

	if [[ ! -d "/opt/AdGuardHome/" ]]; then
		echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
		menu
		exit 0
	fi

	if [[ "${selectADGType}" == "2" ]]; then

		#下载最新版至tmp
		wget -O '/tmp/AdGuardHome_linux_amd64.tar.gz' 'https://static.adguard.com/adguardhome/release/AdGuardHome_linux_amd64.tar.gz'
		#解压最新版至tmp
		tar -C /tmp/ -f /tmp/AdGuardHome_linux_amd64.tar.gz -x -v -z
		#暂停运行
		systemctl stop AdGuardHome
		#将最新版复制到安装目录
		cp /tmp/AdGuardHome/AdGuardHome /opt/AdGuardHome/AdGuardHome
		#开始运行
		systemctl start AdGuardHome

	elif [[ "${selectADGType}" == "3" ]]; then
		/opt/AdGuardHome/AdGuardHome -s uninstall
		rm -rf /opt/AdGuardHome
		systemctl start systemd-resolved
		systemctl enable systemd-resolved
	elif [[ "${selectADGType}" == "4" ]]; then
		systemctl stop AdGuardHome
		systemctl start systemd-resolved
		systemctl enable systemd-resolved
	elif [[ "${selectADGType}" == "5" ]]; then
		systemctl stop systemd-resolved
		systemctl disable systemd-resolved
		systemctl start AdGuardHome
	elif [[ "${selectADGType}" == "6" ]]; then
		systemctl stop systemd-resolved
		systemctl disable systemd-resolved
		systemctl restart AdGuardHome
	fi

}

# 主菜单
menu() {
	cd "$HOME" || exit
	echoContent red "\n=============================================================="
	echoContent green "作者:mack-a"
	echoContent green "当前版本:v2.6.7"
	echoContent green "Github:https://github.com/mack-a/xray-agent"
	echoContent green "描述:八合一共存脚本\c"
	showInstallStatus
	echoContent red "\n=============================================================="
	if [[ "${coreInstallType}" == "1" ]]; then
		echoContent yellow "1.重新安装"
	else
		echoContent yellow "1.安装"
	fi
	echoContent skyBlue "-------------------------工具管理-----------------------------"
	echoContent yellow "2.账号管理"
	echoContent yellow "3.更换伪装站"
	echoContent yellow "4.更新证书"
	echoContent yellow "5.IPv6分流"
	echoContent yellow "6.阻止访问中国大陆IP"
	echoContent yellow "7.WARP分流"
	echoContent yellow "8.添加新端口"
	echoContent skyBlue "-------------------------版本管理-----------------------------"
	echoContent yellow "9.core管理"
	echoContent yellow "10.更新脚本"
	echoContent skyBlue "-------------------------脚本管理-----------------------------"
	echoContent yellow "11.查看日志"
	echoContent yellow "12.卸载脚本"
	echoContent skyBlue "-------------------------其他功能-----------------------------"
	echoContent yellow "13.Adguardhome"
	echoContent yellow "14.WARP"
	echoContent yellow "15.内核管理及BBR优化"
	echoContent yellow "16.Hysteria一键"
	echoContent red "=============================================================="
	mkdirTools
	aliasInstall
	read -r -p "请选择:" selectInstallType
	case ${selectInstallType} in
	1)
		xrayCoreInstall
		;;
	2)
		manageAccount 1
		;;
	3)
		updateNginxBlog 1
		;;
	4)
		renewalTLS 1
		;;
	5)
		ipv6Routing 1
		;;
	6)
		BlockCNIP 1
		;;
	7)
		warpRouting 1
		;;
	8)
		addCorePort 1
		;;
	9)
		xrayVersionManageMenu 1
		;;
	10)
		updateV2RayAgent 1
		;;
	11)
		checkLog 1
		;;
	12)
		unInstall 1
		;;
	13)
		AdguardManageMenu 1
		;;
	14)
		wget -N https://raw.githubusercontent.com/fscarmen/warp/main/menu.sh && bash menu.sh
		;;
	15)
		wget -N https://raw.githubusercontent.com/jinwyp/one_click_script/master/install_kernel.sh && bash install_kernel.sh
		;;
	16)
		bash <(curl -fsSL https://git.io/hysteria.sh)
		;;
	esac
}
# -------------------------------------------------------------
#初始化变量
initVar "$1"
#检查系统类型
checkSystem
#检查CPU架构
checkCPUVendor
#检查XRAY是否安装完成
readInstallType
#读取安装协议类型
readInstallProtocolType
#读取安装端口
readCustomPort
#读取伪装站点域名、UUID及路径
readConfigHostPathUUID
#检查宝塔面板
checkBTPanel

# -------------------------------------------------------------
cronRenewTLS
menu
