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

	# 伪装域名
	domain=

	# 反代路径
	path=

	# UUID
	UUID=

	# 默认监听端口
	Port=

	# 安装总进度
	totalProgress=1

	# xray安装是否完成安装
	coreInstallType=

	# 当前的个性化安装方式 01234
	currentInstallProtocolType=

	# 前置类型
	frontingType=

	# centos version
	centosVersion=

	# nginx配置文件路径
	nginxConfigPath=/etc/nginx/conf.d/

	# xray配置文件路径
	configPath=/etc/xray-agent/xray/conf/

	# xray核心位置
	ctlPath=/etc/xray-agent/xray/xray

	# 是否为预览版
	prereleaseStatus=false

	# ssl申请的服务商
	sslType=

	# Xray中的TLS证书域名(用于解密TLS流量)
	TLSDomain=

	# Reality
	RealityUUID=
	RealityfrontingType=
    RealityPrivateKey=
	RealityPublicKey=
    RealityServerNames=
    RealityDestDomain=
	RealityPort=
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
				;;
			'armv8' | 'aarch64')
				xrayCoreCPUVendor="Xray-linux-arm64-v8a"
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
	# 1.检测安装目录
	if [[ -d "/etc/xray-agent" ]]; then
		if [[ -d "/etc/xray-agent/xray" && -f "${ctlPath}" ]]; then
			# 这里检测xray-core
			if [[ -d "/etc/xray-agent/xray/conf" ]] && [[ -f "${configPath}02_VLESS_TCP_inbounds.json" ]] && [[ -f "${configPath}07_VLESS_Reality_TCP_inbounds.json" ]]; then
				# xray-core
				coreInstallType=3
			elif [[ -d "/etc/xray-agent/xray/conf" ]] && [[ -f "${configPath}02_VLESS_TCP_inbounds.json" ]]; then
				# xray-core
				coreInstallType=1
			elif [[ -d "/etc/xray-agent/xray/conf" ]] && [[ -f "${configPath}07_VLESS_Reality_TCP_inbounds.json" ]]; then
				# xray-core
				coreInstallType=2
			fi
		fi
	fi
}

# 读取协议类型
readInstallProtocolType() {
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
			if echo "${row}" | grep -q VLESS_Reality_TCP_inbounds; then
            	currentInstallProtocolType=${currentInstallProtocolType}'7'
				RealityfrontingType=07_VLESS_Reality_TCP_inbounds
        	fi
        	if echo "${row}" | grep -q VLESS_Reality_h2_inbounds; then
            	currentInstallProtocolType=${currentInstallProtocolType}'8'
        	fi
		done < <(find ${configPath} -name "*inbounds.json" | awk -F "[.]" '{print $1}')
}


# 检查文件目录以及path路径
readConfigHostPathUUID() {
	path=
	Port=
	UUID=
	domain=
	TLSDomain=

	RealityPort=
	RealityPublicKey=
	RealityServerNames=
	RealityDestDomain=
	# 读取path
	if [[ -f "${configPath}${frontingType}.json" ]]; then
		local fallback
		fallback=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.path)' ${configPath}${frontingType}.json | head -1)

		path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}' | awk -F "[w][s]" '{print $1}')

		if [[ -z "${path}" ]]; then
			path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}' | awk -F "[v][w][s]" '{print $1}')
		fi


		Port=$(jq -r .inbounds[0].port ${configPath}${frontingType}.json)
		#domain=$(jq -r .inbounds[0].settings.clients[0].add ${configPath}${frontingType}.json | awk -F "@" '{print $1}')
		#从nginx的回落配置中读取伪装域名
		domain=$(grep "server_name" ${nginxConfigPath}alone.conf | awk '$2 ~ /\./ {gsub(";","",$2); print $2; exit}')
		#UUID=$(jq -r .inbounds[0].settings.clients[0].id ${configPath}${frontingType}.json)
		UUID=$(jq -r '.inbounds[0].settings.clients[] | .id' ${configPath}${frontingType}.json | paste -sd, -)
		TLSDomain=$(jq -r .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile ${configPath}${frontingType}.json | awk -F "[/]" '{print $5}' | awk -F "[.][c][r][t]" '{print $1}')
	fi
	
	if [[ -f "${configPath}${RealityfrontingType}.json" ]]; then
		#RealityUUID=$(jq -r .inbounds[0].settings.clients[0].id ${configPath}${RealityfrontingType}.json)
		RealityUUID=$(jq -r '.inbounds[0].settings.clients[] | .id' ${configPath}${RealityfrontingType}.json | paste -sd, -)
		RealityServerNames=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames | join(",")' ${configPath}${RealityfrontingType}.json)
        RealityPublicKey=$(jq -r .inbounds[0].streamSettings.realitySettings.publicKey ${configPath}${RealityfrontingType}.json)
        RealityPort=$(jq -r .inbounds[0].port ${configPath}${RealityfrontingType}.json)
		RealityDestDomain=$(jq -r .inbounds[0].streamSettings.realitySettings.dest ${configPath}${RealityfrontingType}.json)
		RealityPrivateKey=$(jq -r .inbounds[0].streamSettings.realitySettings.privateKey ${configPath}${RealityfrontingType}.json)
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
	if [[ -n "${coreInstallType}" ]]; then
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
			echoContent yellow "VLESS+TCP[TLS] \c"
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
		if echo ${currentInstallProtocolType} | grep -q 7; then
			echoContent yellow "VLESS+TCP[Reality] \c"
		fi
		if echo ${currentInstallProtocolType} | grep -q 8; then
			echoContent yellow "VLESS+h2[Reality] \c"
		fi
	fi
}

# 初始化安装目录
mkdirTools() {
	mkdir -p /etc/xray-agent/tls
	mkdir -p /etc/xray-agent/xray/conf
	mkdir -p /etc/systemd/system/
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
			${installType} "${policyCoreUtils}" >/dev/null 2>&1
		fi
		if [[ -n $(which semanage) ]]; then
			semanage port -a -t http_port_t -p tcp 31300

		fi
	fi

	if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
		echoContent green " ---> 安装acme.sh"
		curl -s https://get.acme.sh | sh >/etc/xray-agent/tls/acme.log 2>&1
		#source "$HOME/.bashrc"
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
	if [[ "$1" == "Vision" ]]; then
		port="${Port}"
	elif [[ "$1" == "Reality" ]]; then
		port="${RealityPort}"
	fi

	if [[ -n "${port}" ]]; then
		echo
		read -r -p "读取到上次安装时的端口，是否使用上次安装时的端口 ？[y/n]:" historyCustomPortStatus
		if [[ "${historyCustomPortStatus}" == "y" ]]; then
			echoContent yellow "\n ---> 端口: ${port}"
		fi
	fi

	if [[ "${historyCustomPortStatus}" == "n" || -z "${port}" ]]; then
		echo
		echoContent yellow "请输入自定义端口[例: 2083]，[回车]使用443"
		read -r -p "端口:" port
		if [[ -n "${port}" ]]; then
			if ((port >= 1 && port <= 65535)); then
				checkPort "${port}"
			else
				echoContent red " ---> 端口输入错误"
				exit
			fi
		else
			port=443
			checkPort "${port}"
			echoContent yellow "\n ---> 端口: 443"
		fi
	fi

	allowPort "${port}"
	
	if [[ "$1" == "Vision" ]]; then
		Port="${port}"
	elif [[ "$1" == "Reality" ]]; then
		RealityPort="${port}"
	fi

	#删除其他自定义端口
	if [[ "${historyCustomPortStatus}" == "n" ]] && [[ "$1" == "Vision" ]]; then
		rm -rf "$(find ${configPath}* | grep "dokodemodoor")"
	fi

}
# 检测端口是否占用
checkPort() {
	port="$1"

	port_progress=$(lsof -i "tcp:${port}" | grep -q LISTEN | awk '{print $1}' | head -1)
	
	if [[ -n "${port_progress}" && "${port_progress}" != "xray" ]]; then
		echoContent red "\n ---> ${port}端口被占用，请手动关闭后安装\n"
		exit 0
	fi
}

# 初始化Reality证书配置
initTLSRealityConfig() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Reality证书配置"
	if [[ -n "${RealityDestDomain}" ]]; then
		read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDestStatus
		if [[ "${historyDestStatus}" == "y" ]]; then
			echoContent green "\n ---> 使用成功"
		else
			echoContent skyBlue "\n --->生成配置回落的域名 例如:addons.mozilla.org:443\n"
			read -r -p '请输入:' RealityDestDomain
		fi
	else
		echoContent skyBlue "\n --->生成配置回落的域名 例如:addons.mozilla.org:443\n"
		read -r -p '请输入:' RealityDestDomain
	fi
	

	if [[ -z "${RealityDestDomain}" ]]; then
		echoContent red "  域名不可为空--->"
		initTLSRealityConfig 3
	fi

	echoContent yellow "\n ${RealityDestDomain}"

    echoContent skyBlue "\n >配置客户端可用的serverNames\n"
    echoContent red "\n=============================================================="

	if [[ "${historyDestStatus}" == "y" ]]; then
		echoContent green "\n ---> 使用成功"
	else
		echoContent yellow " # 注意事项\n"
		tlsPingResult=$(${ctlPath} tls ping "$(echo "${RealityDestDomain}" | awk -F: '{print $1}')")
		echoContent yellow "\n ---> 可以输入的域名: ${tlsPingResult}\n"
		echoContent red "\n=============================================================="
		echoContent yellow "录入示例:addons.mozilla.org,services.addons.mozilla.org\n"
		echoContent yellow " # 支持逗号输入多个域名,但不支持通配符\n"
		read -r -p "请输入:" RealityServerNames
	fi

	if [[ -z "${RealityServerNames}" ]]; then
        RealityServerNames="\"$(echo "${RealityDestDomain}" | awk -F: '{print $1}')\""
    else
        RealityServerNames=\"${RealityServerNames//,/\",\"}\"
    fi

	echoContent yellow "\n ---> 客户端可用域名: ${RealityServerNames}\n"

	customPortFunction "Reality"
}

# 初始化Nginx申请证书配置
initTLSNginxConfig() {

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
		customPortFunction "Vision"
	fi
}

# 选择ssl安装类型
switchSSLType() {
	if [[ -z "${sslType}" ]]; then
		echoContent red "\n=============================================================="
		echoContent yellow "1.letsencrypt[默认]"
		echoContent yellow "2.zerossl"
		echoContent yellow "3.HiCA"
		echoContent red "=============================================================="
		read -r -p "请选择[回车]使用默认:" selectSSLType
		case ${selectSSLType} in
		1)
			sslType="letsencrypt"
			;;
		2)
			sslType="zerossl"
			;;
		3)
			sslType="https://acme.hi.cn/directory"
			;;
		*)
			sslType="letsencrypt"
			;;
		esac

	fi
}

#acme申请证书
acmeInstallSSL() {

	pingIPv6=$(ping6 -c 1 www.google.com | sed -n '1p' | sed 's/.*(//g;s/).*//g')

	if [[ -z "${pingIPv6}" ]]; then
		installSSLIPv6=""
	else
		installSSLIPv6="--listen-v6"
	fi

	echoContent red "\n=============================================================="
	echoContent yellow "1.密钥（通配证书）"
	echoContent yellow "2.DNS（通配证书）"
	echoContent yellow "3.普通证书【默认】"
	read -r -p "申请SSL证书的方式：" installSSLType

	if [[ "${installSSLType}" == "1" ]]; then
		echoContent red "\n=============================================================="
		echoContent yellow "1.Cloudflare[默认]"
		echoContent yellow "2.DNSPod"
		echoContent yellow "3.Aliyun "
		echoContent yellow "4.其他 "
		echoContent red " ---> 其他DNS运营商使用方式详见 https://github.com/acmesh-official/acme.sh/wiki/dnsapi"
		echoContent red " ---> 请先根据文档自行添加密钥后,并输入n"
		echoContent red "=============================================================="
		read -r -p "请选择:" selectDNS
		if [[ "${selectDNS}" == "1" ]]; then
			echoContent red " ---> the token currently needs access read access to Zone.Zone, and write access to Zone.DNS,"
			echoContent red "=============================================================="
			read -r -p "请输入Cloudflare API Token:" CF_Token
			#sed '/CF_Token/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
			#echo "SAVED_CF_Token='${CF_Token}'" >>/root/.acme.sh/account.conf
			dnsEnvVars="CF_Token='${CF_Token}'"
		
			dnsType=dns_cf
		elif [[ "${selectDNS}" == "2" ]]; then
			echoContent red " ---> The DNSPod.cn Domain API option requires that you first login to your account to get a DNSPod API Key and ID."
			echoContent red "=============================================================="
			read -r -p "请输入DNSPod API Key:" DP_Key
			#sed '/DP_Key/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
			#echo "SAVED_DP_Key='${DP_Key}'" >>/root/.acme.sh/account.conf
			read -r -p "请输入DNSPod API ID:" DP_Id
			#sed '/DP_Id/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
			#echo "SAVED_DP_Id='${DP_Id}'" >>/root/.acme.sh/account.conf
			dnsEnvVars="DP_Key='${DP_Key}' DP_Id='${DP_Id}'"

			dnsType=dns_dp
		elif [[ "${selectDNS}" == "3" ]]; then
			echoContent red " ---> First you need to login to your Aliyun account to get your RAM API key. https://ram.console.aliyun.com/users"
			echoContent red "=============================================================="
			read -r -p "请输入Aliyun API key:" Ali_Key
			#sed '/Ali_Key/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
			#echo "SAVED_Ali_Key='${Ali_Key}'" >>/root/.acme.sh/account.conf
			read -r -p "请输入Aliyun Secret:" Ali_Secret
			#sed '/Ali_Secret/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
			#echo "SAVED_Ali_Secret='${Ali_Secret}'" >>/root/.acme.sh/account.conf
			dnsEnvVars="Ali_Key='${Ali_Key}' Ali_Secret='${Ali_Secret}'"

			dnsType=dns_ali
		elif [[ "${selectDNS}" == "4" ]]; then
			echoContent red "请确保已经通过export添加相应TOKEN、KEY、ID等"
			echoContent yellow "输入类似于dns_cf; dns_dp; dns_ali "
			echoContent red "=============================================================="
			read -r -p "请输入DNS服务商:" dnsType
		else
			echoContent red "选择错误"
			exit 0
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
	
		eval "${dnsEnvVars}" sudo -E "$HOME/.acme.sh/acme.sh" --issue -d "${TLSDomain}" -d "*.${TLSDomain}" --dns "${dnsType}" -k ec-256 --server "${sslType}" "${installSSLIPv6}" --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null

	elif [[ "${installSSLType}" == "2" ]]; then
		sudo "$HOME/.acme.sh/acme.sh" --issue -d "${TLSDomain}" -d "*.${TLSDomain}" --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please -k ec-256 --server "${sslType}" "${installSSLIPv6}" --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null

        local txtValue=
        txtValue=$(tail -n 10 /etc/xray-agent/tls/acme.log | grep "TXT value" | awk -F "'" '{print $2}')
        if [[ -n "${txtValue}" ]]; then
            echoContent green " ---> 请手动添加DNS TXT记录"
            echoContent yellow " ---> 添加方法请参考此教程，https://github.com/mack-a/v2ray-agent/blob/master/documents/dns_txt.md"
            echoContent yellow " ---> 如同一个域名多台机器安装通配符证书，请添加多个TXT记录，不需要修改以前添加的TXT记录"
            echoContent green " --->  name：_acme-challenge"
            echoContent green " --->  value：${txtValue}"
            echoContent yellow " ---> 添加完成后等请等待1-2分钟"
            echo
            read -r -p "是否添加完成[y/n]:" addDNSTXTRecordStatus
            if [[ "${addDNSTXTRecordStatus}" == "y" ]]; then
                local txtAnswer=
                txtAnswer=$(dig @1.1.1.1 +nocmd "_acme-challenge.${TLSDomain}" txt +noall +answer | awk -F "[\"]" '{print $2}')
                if echo "${txtAnswer}" | grep -q "^${txtValue}"; then
                    echoContent green " ---> TXT记录验证通过"
                    echoContent green " ---> 生成证书中"
                    sudo "$HOME/.acme.sh/acme.sh" --renew -d "${TLSDomain}" -d "*.${TLSDomain}" --yes-I-know-dns-manual-mode-enough-go-ahead-please --ecc --server "${sslType}" "${installSSLIPv6}" --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null
                else
                    echoContent red " ---> 验证失败，请等待1-2分钟后重新尝试"
                    acmeInstallSSL
                fi
            else
                echoContent red " ---> 放弃"
                exit 0
            fi
        fi

	elif [[ "${installSSLType}" == "3" ]]; then
		allowPort 80
		TLSDomain=${domain}
		echoContent green " ---> 生成证书中"
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${TLSDomain}" --standalone -k ec-256 --server "${sslType}" "${installSSLIPv6}" --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null
	fi

}

# 安装TLS
installTLS() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"

	#判断证书域名与伪装域名相同,如果未找到证书，则设置为根域名
	if [[ -f "/etc/xray-agent/tls/${domain}.crt" && -f "/etc/xray-agent/tls/${domain}.key" && -n $(cat "/etc/xray-agent/tls/${domain}.crt") ]] || [[ -d "$HOME/.acme.sh/${domain}_ecc" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]]; then
		TLSDomain=${domain}
	else
		TLSDomain=$(echo "${domain}" | awk -F "[.]" '{print $(NF-1)"."$NF}')
		if [[ "${TLSDomain}" == "eu.org" ]]; then
			TLSDomain=$(echo "${domain}" | awk -F "[.]" '{print $(NF-2)"."$(NF-1)"."$NF}')
		fi
	fi

	# 安装tls
	if [[ -f "/etc/xray-agent/tls/${TLSDomain}.crt" && -f "/etc/xray-agent/tls/${TLSDomain}.key" && -n $(cat "/etc/xray-agent/tls/${TLSDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${TLSDomain}_ecc" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.key" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" ]]; then
		echoContent green " ---> 检测到证书"
		
		renewalTLS "${TLSDomain}"

		if [[ -z $(find /etc/xray-agent/tls/ -name "${TLSDomain}.crt") ]] || [[ -z $(find /etc/xray-agent/tls/ -name "${TLSDomain}.key") ]] || [[ -z $(cat "/etc/xray-agent/tls/${TLSDomain}.crt") ]]; then
			sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath "/etc/xray-agent/tls/${TLSDomain}.crt" --keypath "/etc/xray-agent/tls/${TLSDomain}.key" --ecc >/dev/null
		else
			echoContent yellow " ---> 如未过期或者自定义证书请选择[n]\n"
			read -r -p "是否重新安装？[y/n]:" reInstallStatus
			if [[ "${reInstallStatus}" == "y" ]]; then
				find /etc/xray-agent/tls/ -type f -name "*${TLSDomain}*" -exec rm -f {} \;
				installTLS "$1" 0
			fi
		fi
	elif [[ -d "$HOME/.acme.sh" ]]; then

		handleNginx stop
		
		echoContent green " ---> 安装TLS证书"

		switchSSLType
		customSSLEmail
		acmeInstallSSL

		sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath "/etc/xray-agent/tls/${TLSDomain}.crt" --keypath "/etc/xray-agent/tls/${TLSDomain}.key" --ecc >/dev/null

		handleNginx start

		if [[ ! -f "/etc/xray-agent/tls/${TLSDomain}.crt" || ! -f "/etc/xray-agent/tls/${TLSDomain}.key" ]] || [[ -z $(cat "/etc/xray-agent/tls/${TLSDomain}.key") || -z $(cat "/etc/xray-agent/tls/${TLSDomain}.crt") ]]; then
			tail -n 10 /etc/xray-agent/tls/acme.log
			if [[ "$2" == "1" ]]; then
				echoContent red " ---> TLS安装失败，请检查acme日志"
				exit 0
			fi

			echo
			echoContent yellow " ---> 重新尝试安装TLS证书"

			if tail -n 10 /etc/xray-agent/tls/acme.log | grep -q "Could not validate email address as valid"; then
				echoContent red " ---> 邮箱无法通过SSL厂商验证，请重新输入"
				echo
				customSSLEmail "validate email"
				installTLS "$1" 1
			else
				installTLS "$1" 1
			fi

		fi

		echoContent green " ---> TLS生成成功"
	else
		echoContent yellow " ---> 未安装acme.sh"
		exit 0
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

# 自定义/随机路径
randomPathFunction() {
	echoContent skyBlue "\n进度  $1/${totalProgress} : 生成随机路径"

	if [[ -n "${path}" ]]; then
		echo
		read -r -p "读取到上次安装记录，是否使用上次安装时的path路径 ？[y/n]:" historyPathStatus
		echo
	fi

	if [[ "${historyPathStatus}" == "y" ]]; then
		echoContent green " ---> 使用成功\n"
	else
		echoContent yellow "请输入自定义路径[例: alone]，不需要斜杠，[回车]随机路径"
		read -r -p '路径:' path

		if [[ -z "${path}" ]]; then
			local chars="abcdefghijklmnopqrtuxyz"
    		for i in {1..4}; do
        		echo "${i}" >/dev/null
        		path+="${chars:RANDOM%${#chars}:1}"
    		done
		else
			if [[ "${path: -2}" == "ws" ]]; then
                echo
                echoContent red " ---> 自定义path结尾不可用ws结尾，否则无法区分分流路径"
                randomPathFunction "$1"
            fi
		fi

	fi
	echoContent yellow "\n path:${path}"
	echoContent skyBlue "\n----------------------------"
}

# 更新证书
renewalTLS() {
	echoContent skyBlue "更新证书"

	if [[ "$1" == "all" ]]; then
		local TLSDomain
		for certFile in /etc/xray-agent/tls/*.crt; do
			TLSDomain=$(basename "$certFile" .crt)
			updateTLSCertificate "${TLSDomain}"
		done
	else
		TLSDomain=$1
		updateTLSCertificate "${TLSDomain}"
	fi

}

# 更新证书
updateTLSCertificate() {
	
	local TLSDomain=$1

	if [[ -d "$HOME/.acme.sh/${TLSDomain}_ecc" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.key" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" ]]; then

		modifyTime=$(stat "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" | sed -n '7,6p' | awk '{print $2" "$3" "$4" "$5}')

		modifyTime=$(date +%s -d "${modifyTime}")
		currentTime=$(date +%s)
		((stampDiff = currentTime - modifyTime))
		((days = stampDiff / 86400))
		sslRenewalDays=90
		((remainingDays = sslRenewalDays - days))

		if [[ ${remainingDays} -le 0 ]]; then
			echoContent red " ---> 证书未过期，是否强制更新${TLSDomain}"
			tlsStatus="已过期"
		else
			tlsStatus=${remainingDays}
		fi
		echoContent skyBlue " --->${TLSDomain}"
		echoContent skyBlue " ---> 证书检查日期:$(date "+%F %H:%M:%S")"
		echoContent skyBlue " ---> 证书生成日期:$(date -d @"${modifyTime}" +"%F %H:%M:%S")"
		echoContent skyBlue " ---> 证书生成天数:${days}"
		echoContent skyBlue " ---> 证书剩余天数:"${tlsStatus}
		echoContent skyBlue " ---> 证书过期前最后14天内自动更新，如更新失败请手动更新"

		if [[ ${remainingDays} -le 14 ]]; then
			echoContent yellow " ---> 重新生成证书${TLSDomain}"
			handleNginx stop
			sudo "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh" -d "${TLSDomain}"
			sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath /etc/xray-agent/tls/"${TLSDomain}.crt" --keypath /etc/xray-agent/tls/"${TLSDomain}.key" --ecc
			reloadCore
			handleNginx start
		else
			echoContent green " ---> 证书有效${TLSDomain}"
		fi
	else
		echoContent red " ---> 未安装"
	fi
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
			echoContent red "请手动执行【${ctlPath} -confdir /etc/xray-agent/xray/conf】，查看错误日志"
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

	if [[ -z "${coreInstallType}" ]]; then

		version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -1)

		echoContent green " ---> Xray-core版本:${version}"
		
		if wget --help | grep -q show-progress; then
			wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
		else
			wget -c -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip" >/dev/null 2>&1
		fi

		if [[ ! -f "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" ]]; then
            echoContent red " ---> 核心下载失败，请重新尝试安装"
            exit 0
        fi

		unzip -o "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/xray-agent/xray >/dev/null
		rm -rf "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip"

		version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases | jq -r '.[]|.tag_name' | head -1)
        echoContent skyBlue "------------------------Version-------------------------------"
        echo "version:${version}"
        rm /etc/xray-agent/xray/geo* >/dev/null 2>&1
        wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
        wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
		
		chmod 655 ${ctlPath}
	else
		echoContent green " ---> Xray-core版本:$(${ctlPath} --version | awk '{print $2}' | head -1)"
		read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
		if [[ "${reInstallXrayStatus}" == "y" ]]; then
			rm -f ${ctlPath}
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
		execStart="${ctlPath} run -confdir /etc/xray-agent/xray/conf"
		cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=root
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

# 根据协议类型生成clients
generate_clients() {
  local protocol="$1"
  local uuid_list_string="$2"
  IFS=',' read -ra UUID_LIST <<< "$uuid_list_string"
  local clients=""

  for uuid in "${UUID_LIST[@]}"; do
    case "$protocol" in
      "VLESS_TCP")
        clients="${clients}{
          \"id\": \"${uuid}\",
          \"flow\": \"xtls-rprx-vision\"
        },"
        ;;
      "VLESS_H2")
        clients="${clients}{
          \"id\": \"${uuid}\",
          \"flow\": \"\"
        },"
        ;;
      "VLESS_WS")
        clients="${clients}{
          \"id\": \"${uuid}\"
        },"
        ;;
      "TROJAN_TCP")
        clients="${clients}{
          \"password\": \"${uuid}\"
        },"
        ;;
      "VLESS_GRPC")
        clients="${clients}{
          \"id\": \"${uuid}\"
        },"
        ;;
      "VMess_WS")
        clients="${clients}{
          \"id\": \"${uuid}\",
          \"alterId\": 0
        },"
        ;;
      "TROJAN_GRPC")
        clients="${clients}{
          \"password\": \"${uuid}\"
        },"
        ;;
      *)
        echo "Invalid protocol"
        exit 1
        ;;
    esac
  done

  # 移除多余的逗号
  clients=${clients%?}
  echo "$clients"
}


# 初始化 Reality 配置
initXrayRealityConfig() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化 Xray-core Reality配置"
    
	echoContent skyBlue "\n========================== 生成key ==========================\n"
    if [[ -n "${RealityPublicKey}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的PublicKey/PrivateKey ？[y/n]:" historyKeyStatus
        if [[ "${historyKeyStatus}" == "y" ]]; then
            echoContent green "\n ---> 使用成功"
		else
			RealityX25519Key=$(${ctlPath} x25519)

    		RealityPrivateKey=$(echo "${RealityX25519Key}" | head -1 | awk '{print $3}')
    		RealityPublicKey=$(echo "${RealityX25519Key}" | tail -n 1 | awk '{print $3}')
        fi
	else
		RealityX25519Key=$(${ctlPath} x25519)

    	RealityPrivateKey=$(echo "${RealityX25519Key}" | head -1 | awk '{print $3}')
    	RealityPublicKey=$(echo "${RealityX25519Key}" | tail -n 1 | awk '{print $3}')
    fi

    echoContent green "\n privateKey:${RealityPrivateKey}"
    echoContent green "\n publicKey:${RealityPublicKey}"

	echoContent skyBlue "\n========================== 生成UUID ==========================\n"

	if [[ -n "${RealityUUID}" ]]; then
		read -r -p "读取到上次安装记录，是否使用上次安装时的UUID ？[y/n]:" historyUUIDStatus
		if [[ "${historyUUIDStatus}" == "y" ]]; then
			echoContent green "\n ---> 使用成功"
		else
			echoContent yellow "请输入自定义UUID[需合法](支持以逗号为分割输入多个)，[回车]随机UUID"
			read -r -p 'UUID:' RealityUUID
		fi
	elif [[ -n "${UUID}" ]]; then
		echoContent yellow "检测到VISION的UUID，将自动使用相同的UUID"
		RealityUUID=$UUID
	else
		echoContent yellow "请输入自定义UUID[需合法](支持以逗号为分割输入多个)，[回车]随机UUID"
		read -r -p 'UUID:' RealityUUID
	fi
	

	if [[ -z "${RealityUUID}" ]]; then
		echoContent red "\n ---> uuid读取错误，重新生成"
		RealityUUID=$(${ctlPath} uuid)
	fi

	echoContent yellow "\n ${RealityUUID}"

	cat <<EOF >${configPath}07_VLESS_Reality_TCP_inbounds.json
{
  "inbounds": [
    {
      "port": ${RealityPort},
      "protocol": "vless",
      "tag": "VLESSReality",
      "settings": {
        "clients": [
          $(generate_clients "VLESS_TCP" "${RealityUUID}")
        ],
        "decryption": "none",
        "fallbacks":[
            {
                "dest": "31305",
                "xver": 1
            }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
            "show": false,
            "dest": "${RealityDestDomain}",
            "xver": 0,
            "serverNames": [
                ${RealityServerNames}
            ],
            "privateKey": "${RealityPrivateKey}",
            "publicKey": "${RealityPublicKey}",
            "shortIds": [
                ""
            ]
        }
      },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ],
		"routeOnly": false
	  }
    }
  ]
}
EOF

cat <<EOF >${configPath}08_VLESS_Reality_h2_inbounds.json
{
  "inbounds": [
    {
      "port": 31305,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "tag": "VLESSRealityH2",
      "settings": {
        "clients": [
          $(generate_clients "VLESS_H2" "${RealityUUID}")
        ],
        "decryption": "none"
      },
      "streamSettings": {
            "network": "h2",
            "sockopt": {
                "acceptProxyProtocol": true
            }
      },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ],
		"routeOnly": false
	  }
    }
  ]
}
EOF

	if [[ -f "${configPath}10_ipv4_outbounds.json" ]] || [[ -f "${configPath}09_routing.json" ]]; then
		read -r -p "是否保留路由和分流规则 ？[y/n]:" keepconfigstatus
	fi

	if [[ "${keepconfigstatus}" == "n" ]]; then
		# log
		cat <<EOF >${configPath}00_log.json
{
  "log": {
    "error": "/etc/xray-agent/xray/error.log",
    "loglevel": "warning"
  }
}
EOF

		# 本地策略Policy
		cat <<EOF >${configPath}01_policy.json
{
  "policy": {
    "levels": {
      "0": {
        "handshake": 3,
        "connIdle": 360,
		"bufferSize": 1024
      }
    }
  }
}
EOF

		cat <<EOF >${configPath}10_ipv4_outbounds.json
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
		rm -f ${configPath}09_routing.json

		# dns
		cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF

fi
}

# 初始化Xray 配置文件
initXrayConfig() {
	echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Xray配置"
	echo
	
	if [[ -n "${UUID}" ]]; then
		read -r -p "读取到上次安装记录，是否使用上次安装时的UUID ？[y/n]:" historyUUIDStatus
		if [[ "${historyUUIDStatus}" == "y" ]]; then
			echoContent green "\n ---> 使用成功"
		else
			echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
			read -r -p 'UUID:' UUID
		fi
	elif [[ -n "${RealityUUID}" ]]; then
		echoContent yellow "检测到Reality的UUID，将自动使用相同的UUID"
		UUID=$RealityUUID
	else
		echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
		read -r -p 'UUID:' UUID
	fi
	

	if [[ -z "${UUID}" ]]; then
		echoContent red "\n ---> uuid读取错误，重新生成"
		UUID=$(${ctlPath} uuid)
	fi

	echoContent yellow "\n ${UUID}"

	if [[ -f "${configPath}10_ipv4_outbounds.json" ]] || [[ -f "${configPath}09_routing.json" ]]; then
		read -r -p "是否保留路由和分流规则 ？[y/n]:" keepconfigstatus
	fi

	if [[ "${keepconfigstatus}" == "n" ]]; then
		
		# log
		cat <<EOF >${configPath}00_log.json
{
  "log": {
    "error": "/etc/xray-agent/xray/error.log",
    "loglevel": "warning"
  }
}
EOF

		# 本地策略Policy
		cat <<EOF >${configPath}01_policy.json
{
  "policy": {
    "levels": {
      "0": {
        "handshake": 3,
        "connIdle": 360,
		"bufferSize": 1024
      }
    }
  }
}
EOF

		cat <<EOF >${configPath}10_ipv4_outbounds.json
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
		rm -f ${configPath}09_routing.json

		# dns
		cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF

fi

	# VLESS_TCP_TLS/XTLS
	# 回落nginx
	fallbacksList='{"dest":31296,"xver":1},{"alpn":"h2","dest":31302,"xver":0}'
	cat <<EOF >${configPath}04_trojan_TCP_inbounds.json
{
"inbounds":[
	{
	  "port": 31296,
	  "listen": "127.0.0.1",
	  "protocol": "trojan",
	  "tag":"trojanTCP",
	  "settings": {
		"clients": [
		  $(generate_clients "TROJAN_TCP" "${UUID}")
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
        ],
		"routeOnly": false
	  }
	}
	]
}
EOF

	# VLESS_WS_TLS
	fallbacksList=${fallbacksList}',{"path":"/'${path}'ws","dest":31297,"xver":1}'
	cat <<EOF >${configPath}03_VLESS_WS_inbounds.json
{
"inbounds":[
    {
	  "port": 31297,
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSWS",
	  "settings": {
		"clients": [
		  $(generate_clients "VLESS_WS" "${UUID}")
		],
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "ws",
		"security": "none",
		"wsSettings": {
		  "acceptProxyProtocol": true,
		  "path": "/${path}ws"
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ],
		"routeOnly": false
	  }
	}
]
}
EOF

	# trojan_grpc
	cat <<EOF >${configPath}04_trojan_gRPC_inbounds.json
{
"inbounds": [
    {
	  "port": 31304,
	  "listen": "127.0.0.1",
	  "protocol": "trojan",
	  "tag": "trojangRPCTCP",
	  "settings": {
		"clients": [
		  $(generate_clients "TROJAN_GRPC" "${UUID}")
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
		  "serviceName": "${path}trojangrpc"
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ],
		"routeOnly": false
	  }
    }
]
}
EOF

	# VMess_WS
	fallbacksList=${fallbacksList}',{"path":"/'${path}'vws","dest":31299,"xver":1}'
	cat <<EOF >${configPath}05_VMess_WS_inbounds.json
{
"inbounds":[
    {
	  "listen": "127.0.0.1",
	  "port": 31299,
	  "protocol": "vmess",
	  "tag":"VMessWS",
	  "settings": {
		"clients": [
		  $(generate_clients "VMess_WS" "${UUID}")
		]
	  },
	  "streamSettings": {
		"network": "ws",
		"security": "none",
		"wsSettings": {
		  "acceptProxyProtocol": true,
		  "path": "/${path}vws"
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ],
		"routeOnly": false
	  }
    }
]
}
EOF

	#VLESS_GRCP
	cat <<EOF >${configPath}06_VLESS_gRPC_inbounds.json
{
"inbounds":[
    {
	  "port": 31301,
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSGRPC",
	  "settings": {
		"clients": [
		  $(generate_clients "VLESS_GRPC" "${UUID}")
		],
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "grpc",
		"grpcSettings": {
		  "serviceName": "${path}grpc"
		}
	  },
	  "sniffing": {
        "enabled": true,
        "destOverride": [
			"http",
			"tls"
        ],
		"routeOnly": false
	  }
    }
]
}
EOF

	# VLESS_TCP

	cat <<EOF >${configPath}02_VLESS_TCP_inbounds.json
{
"inbounds":[
{
  "port": ${Port},
  "protocol": "vless",
  "tag":"VLESSTCP",
  "settings": {
    "clients": [
     $(generate_clients "VLESS_TCP" "${UUID}")
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
      "certificates": [
        {
          "ocspStapling": 3600,
          "certificateFile": "/etc/xray-agent/tls/${TLSDomain}.crt",
          "keyFile": "/etc/xray-agent/tls/${TLSDomain}.key"
        }
      ]
    }
  },
    "sniffing": {
      "enabled": true,
      "destOverride": [
        "http",
        "tls"
      ],
	  "routeOnly": false
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

	rm -f ${nginxConfigPath}default.conf
	echoContent skyBlue "删除nginx默认站点"
	
	cat <<EOF >${nginxConfigPath}alone.conf
# acme使用standalone模式申请/更新证书时会监听80端口，如果80端口被占用会导致失败。
#server {
    	#listen 80;
    	#return 301 https://\$host\$request_uri;
    #}

server {
	listen 127.0.0.1:31300;
	listen 127.0.0.1:31302 http2 so_keepalive=on;
	server_name ${domain};

    client_header_timeout 1071906480m;
    keepalive_timeout 1071906480m;

    location /${path}grpc {
 		client_max_body_size 0;
        grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
        client_body_timeout 1071906480m;
        grpc_read_timeout 1071906480m;
        client_body_buffer_size 1m;
        grpc_pass grpc://127.0.0.1:31301;
	}

	location /${path}trojangrpc {
 		client_max_body_size 0;
        grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
        client_body_timeout 1071906480m;
        grpc_read_timeout 1071906480m;
        client_body_buffer_size 1m;
        grpc_pass grpc://127.0.0.1:31304;
	}

	location / {
        add_header Strict-Transport-Security "max-age=15552000; preload" always;
        sub_filter \$proxy_host \$host;
        sub_filter_once off;

        proxy_pass https://www.kaggle.com;
        proxy_set_header Host \$proxy_host;

        proxy_http_version 1.1;
        proxy_cache_bypass \$http_upgrade;

        proxy_ssl_server_name on;
        proxy_ssl_name \$proxy_host;
        proxy_ssl_protocols TLSv1.2 TLSv1.3;

        proxy_set_header Upgrade \$http_upgrade;
        #proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$proxy_protocol_addr;
        #proxy_set_header Forwarded \$proxy_add_forwarded;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
	}
}
EOF

handleNginx stop
handleNginx start

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
	echo "30 1 * * 1 /bin/bash /etc/xray-agent/auto_update_geodata.sh >> /etc/xray-agent/crontab_geo.log 2>&1" >>/etc/xray-agent/backup_crontab.cron
	crontab /etc/xray-agent/backup_crontab.cron
	echoContent green "\n ---> 添加定时更新GeoData成功"

}

# 验证整个服务是否可用
checkGFWStatue() {
	readInstallType
	echoContent skyBlue "\n进度 $1/${totalProgress} : 验证服务启动状态"
	if [[ -n "${coreInstallType}" ]] && [[ -n $(pgrep -f xray/xray) ]]; then
		echoContent green " ---> 服务启动成功"
	else
		echoContent red " ---> 服务启动失败，请检查终端是否有日志打印"
		exit 0
	fi

}

# 获取公网IP
getPublicIP() {
    local currentIP=
    currentIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${currentIP}" ]]; then
        currentIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${currentIP}"
}

# 通用
defaultBase64Code() {
	local type=$1
	local id=$2

	if [[ "${type}" == "vlesstcp" ]]; then
		echoContent yellow " ---> 通用格式(VLESS+TCP+TLS/xtls-rprx-vision)"
		echoContent green "    vless://${id}@${domain}:${Port}?encryption=none&flow=xtls-rprx-vision&security=tls&sni=${domain}&alpn=h2%2Chttp%2F1.1&fp=chrome&type=tcp&headerType=none#${id}\n"

		echoContent yellow " ---> 格式化明文(VLESS+TCP+TLS/xtls-rprx-vision)"
		echoContent green "协议类型:VLESS，地址:${domain}，端口:${Port}，用户ID:${id}，安全:tls，传输方式:tcp，flow:xtls-rprx-vision，账户名:${id}\n"

	elif [[ "${type}" == "vmessws" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${Port},\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${domain}\",\"type\":\"none\",\"path\":\"/${path}vws\",\"net\":\"ws\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${domain}\",\"sni\":\"${domain}\",\"alpn\":\"h2,http/1.1\",\"fp\":\"chrome\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> 通用json(VMess+WS+TLS)"
        echoContent green "    {\"port\":${Port},\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${domain}\",\"type\":\"none\",\"path\":\"/${path}vws\",\"net\":\"ws\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${domain}\",\"sni\":\"${domain}\",\"alpn\":\"h2,http/1.1\",\"fp\":\"chrome\"}\n"
		echoContent green "    vmess://${qrCodeBase64Default}\n"


	elif [[ "${type}" == "vlessws" ]]; then

		echoContent yellow " ---> 通用格式(VLESS+WS+TLS)"
		echoContent green "    vless://${id}@${domain}:${Port}?encryption=none&security=tls&sni=${domain}&alpn=h2%2Chttp%2F1.1&fp=chrome&type=ws&host=${domain}&path=%2F${path}ws#${id}\n"

		echoContent yellow " ---> 格式化明文(VLESS+WS+TLS)"
		echoContent green "    协议类型:VLESS，地址:${domain}，伪装域名/SNI:${domain}，端口:${Port}，用户ID:${id}，安全:tls，传输方式:ws，路径:/${path}ws，账户名:${id}\n"


	elif [[ "${type}" == "vlessgrpc" ]]; then

		echoContent yellow " ---> 通用格式(VLESS+gRPC+TLS)"
		echoContent green "    vless://${id}@${domain}:${Port}?encryption=none&security=tls&sni=${domain}&alpn=h2&fp=chrome&type=grpc&serviceName=${path}grpc#${id}\n"

		echoContent yellow " ---> 格式化明文(VLESS+gRPC+TLS)"
		echoContent green "    协议类型:VLESS，地址:${domain}，伪装域名/SNI:${domain}，端口:${Port}，用户ID:${id}，安全:tls，传输方式:gRPC，alpn:h2，serviceName:${path}grpc，账户名:${id}\n"

	elif [[ "${type}" == "trojan" ]]; then
		# URLEncode
		echoContent yellow " ---> Trojan(TLS)"
		echoContent green "    trojan://${id}@${domain}:${Port}?security=tls&sni=${domain}&alpn=http%2F1.1&fp=chrome&type=tcp&headerType=none#${id}\n"

	elif [[ "${type}" == "trojangrpc" ]]; then
		# URLEncode

		echoContent yellow " ---> Trojan gRPC(TLS)"
		echoContent green "    trojan://${id}@${domain}:${Port}?security=tls&sni=${domain}&alpn=h2&fp=chrome&type=grpc&serviceName=${path}trojangrpc&mode=gun#${id}\n"
	
    elif [[ "${type}" == "vlesstcpreality" ]]; then
        echoContent yellow " ---> 通用格式(VLESS+tcp+reality)"
        echoContent green "    vless://${id}@$(getPublicIP):${RealityPort}?encryption=none&security=reality&type=tcp&sni=$(echo "${RealityServerNames}" | cut -d ',' -f 1)&fp=chrome&pbk=${RealityPublicKey}&flow=xtls-rprx-vision#${id}\n"

        echoContent yellow " ---> 格式化明文(VLESS+tcp+reality)"
        echoContent green "协议类型:VLESS reality，地址:$(getPublicIP)，publicKey:${RealityPublicKey}，serverNames：${RealityServerNames}，端口:${RealityPort}，用户ID:${id}，传输方式:tcp，账户名:${id}\n"

    elif [[ "${type}" == "vlessh2reality" ]]; then
        echoContent yellow " ---> 通用格式(VLESS+h2+reality)"
        echoContent green "    vless://${id}@$(getPublicIP):${RealityPort}?encryption=none&security=reality&type=h2&sni=$(echo "${RealityServerNames}" | cut -d ',' -f 1)&fp=chrome&pbk=${RealityPublicKey}#${id}\n"

        echoContent yellow " ---> 格式化明文(VLESS+h2+reality)"
        echoContent green "协议类型:VLESS reality，serviceName:grpc，地址:$(getPublicIP)，publicKey:${RealityPublicKey}，serverNames：${RealityServerNames}，端口:${RealityPort}，用户ID:${id}，传输方式:h2，client-fingerprint：chrome，账户名:${id}\n"
    fi

}


# 账号
showAccounts() {
	readInstallType
	#读取安装协议类型
	readInstallProtocolType
	#读取伪装站点域名、UUID及路径
	readConfigHostPathUUID
	echoContent skyBlue "\n进度 $1/${totalProgress} : 账号"
	local 
	# VLESS TCP
	if [[ -n "${configPath}" ]]; then
		show=1
		if echo "${currentInstallProtocolType}" | grep -q 0; then
			echoContent skyBlue "===================== VLESS TCP TLS/XTLS-VISION ======================\n"
			jq .inbounds[0].settings.clients ${configPath}${frontingType}.json | jq -c '.[]' | while read -r user; do
				local uuid=
				uuid=$(echo "${user}" | jq -r .id)
				echoContent skyBlue "\n ---> 账号:${uuid}"
				echo
				defaultBase64Code vlesstcp  "$(echo "${user}" | jq -r .id)"
			done
		fi

		# VLESS WS
		if echo ${currentInstallProtocolType} | grep -q 1; then
			echoContent skyBlue "\n================================ VLESS WS TLS CDN ================================\n"

			jq .inbounds[0].settings.clients ${configPath}03_VLESS_WS_inbounds.json | jq -c '.[]' | while read -r user; do
				local uuid=
				uuid=$(echo "${user}" | jq -r .id)
				echoContent skyBlue "\n ---> 账号:${uuid}"
				echo
				defaultBase64Code vlessws  "$(echo "${user}" | jq -r .id)"
			done
		fi

		if echo ${currentInstallProtocolType} | grep -q 2; then
			echoContent skyBlue "\n================================  Trojan gRPC TLS  ================================\n"
				jq .inbounds[0].settings.clients ${configPath}04_trojan_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
					local uuid=
					uuid=$(echo "${user}" | jq -r .password)
					echoContent skyBlue "\n ---> 账号:${uuid}"
					echo
					defaultBase64Code trojangrpc "$(echo "${user}" | jq -r .password)"
			done
		fi

		# VMess WS
		if echo ${currentInstallProtocolType} | grep -q 3; then
			echoContent skyBlue "\n================================ VMess WS TLS CDN ================================\n"
			local path="${path}vws"
			path="${path}vws"
			jq .inbounds[0].settings.clients ${configPath}05_VMess_WS_inbounds.json | jq -c '.[]' | while read -r user; do
				local uuid=
				uuid=$(echo "${user}" | jq -r .id)
				echoContent skyBlue "\n ---> 账号:${uuid}"
				echo
				defaultBase64Code vmessws "$(echo "${user}" | jq -r .id)"
			done
		fi

			# trojan tcp
		if echo ${currentInstallProtocolType} | grep -q 4; then
			echoContent skyBlue "\n==================================  Trojan TLS  ==================================\n"
			jq .inbounds[0].settings.clients ${configPath}04_trojan_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
				local uuid=
				uuid=$(echo "${user}" | jq -r .password)
				echoContent skyBlue "\n ---> 账号:${uuid}"
				echo
				defaultBase64Code trojan "$(echo "${user}" | jq -r .password)"
			done
		fi

		# VLESS grpc
		if echo ${currentInstallProtocolType} | grep -q 5; then
			echoContent skyBlue "\n=============================== VLESS gRPC TLS CDN ===============================\n"
			jq .inbounds[0].settings.clients ${configPath}06_VLESS_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
				local uuid=
				uuid=$(echo "${user}" | jq -r .id)
				echoContent skyBlue "\n ---> 账号:${uuid}"
				echo
				defaultBase64Code vlessgrpc "$(echo "${user}" | jq -r .id)"
			done
		fi

		# VLESS reality tcp
		if echo ${currentInstallProtocolType} | grep -q 7; then
			echoContent skyBlue "\n=============================== VLESS TCP Reality ===============================\n"
			jq .inbounds[0].settings.clients ${configPath}${RealityfrontingType}.json | jq -c '.[]' | while read -r user; do
				local uuid=
				uuid=$(echo "${user}" | jq -r .id)
				echoContent skyBlue "\n ---> 账号:${uuid}"
				echo
				defaultBase64Code vlesstcpreality "$(echo "${user}" | jq -r .id)"
			done
		fi

		# VLESS reality h2
		if echo ${currentInstallProtocolType} | grep -q 8; then
			echoContent skyBlue "\n=============================== VLESS H2 Reality ===============================\n"
			jq .inbounds[0].settings.clients ${configPath}08_VLESS_Reality_h2_inbounds.json | jq -c '.[]' | while read -r user; do
				local uuid=
				uuid=$(echo "${user}" | jq -r .id)
				echoContent skyBlue "\n ---> 账号:${uuid}"
				echo
				defaultBase64Code vlessh2reality "$(echo "${user}" | jq -r .id)"
			done
		fi
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
	echoContent yellow "7.更新geosite、geoip"
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
	elif [[ "${selectXrayType}" == "7" ]]; then
		./etc/xray-agent/auto_update_geodata.sh
	fi

}

# 更新Xray
updateXray() {
	readInstallType
	if [[ -z "${coreInstallType}" ]]; then
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
		chmod 655 ${ctlPath}
		handleXray stop
		handleXray start
	else
		echoContent green " ---> 当前Xray-core版本:$(${ctlPath} --version | awk '{print $2}' | head -1)"

		if [[ -n "$1" ]]; then
			version=$1
		else
			version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
		fi

		if [[ -n "$1" ]]; then
			read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
			if [[ "${rollbackXrayStatus}" == "y" ]]; then
				echoContent green " ---> 当前Xray-core版本:$(${ctlPath} --version | awk '{print $2}' | head -1)"

				handleXray stop
				rm -f ${ctlPath}
				updateXray "${version}"
			else
				echoContent green " ---> 放弃回退版本"
			fi
		elif [[ "${version}" == "v$(${ctlPath} --version | awk '{print $2}' | head -1)" ]]; then
			read -r -p "当前版本与最新版相同，是否重新安装？[y/n]:" reInstallXrayStatus
			if [[ "${reInstallXrayStatus}" == "y" ]]; then
				handleXray stop
				rm -f ${ctlPath}
				updateXray
			else
				echoContent green " ---> 放弃重新安装"
			fi
		else
			read -r -p "最新版本为:${version}，是否更新？[y/n]:" installXrayStatus
			if [[ "${installXrayStatus}" == "y" ]]; then
				rm -f ${ctlPath}
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
		cp ${nginxConfigPath}alone.conf /etc/xray-agent/alone_backup.conf
		echoContent green " ---> nginx配置文件备份成功"
	fi

	if [[ "$1" == "restoreBackup" ]] && [[ -f "/etc/xray-agent/alone_backup.conf" ]]; then
		cp /etc/xray-agent/alone_backup.conf ${nginxConfigPath}alone.conf
		echoContent green " ---> nginx配置文件恢复备份成功"
		rm /etc/xray-agent/alone_backup.conf
	fi
}

# 更新伪装站
updateNginxBlog() {
	if [[ "${coreInstallType}" != "1" ]] && [[ "${coreInstallType}" != "3" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi
	echoContent skyBlue "\n进度 $1/${totalProgress} : 更换伪装站点"
	echoContent red "\n=============================================================="
    if [[ -f "${nginxConfigPath}alone.conf" ]]; then
	
		read -r -p "请输入要镜像的域名,例如 www.baidu.com，无http/https:" mirrorDomain
	
		currentmirrorDomain=$(grep -m 1 "proxy_pass https://*" ${nginxConfigPath}alone.conf | sed 's/;//' | awk -F "//" '{print $2}')
		
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
    local port=$1
    local type=$2
    if [[ -z "${type}" ]]; then
        type=tcp
    fi
    # 如果防火墙启动状态则添加相应的开放端口
    if systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        local updateFirewalldStatus=
        if ! iptables -L | grep -q "${port}(mack-a)"; then
            updateFirewalldStatus=true
            iptables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}(mack-a)" -j ACCEPT
        fi
        if ! ip6tables -L | grep -q "${port}(mack-a)"; then
            updateFirewalldStatus=true
            ip6tables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}(mack-a)" -j ACCEPT
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            netfilter-persistent save
        fi
    elif systemctl status ufw 2>/dev/null | grep -q "active (exited)"; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -q "${port}/${type}"; then
                sudo ufw allow "${port}/${type}"
                sudo ufw allow from any to any proto ipv6 "${type}" port "${port}"
                checkUFWAllowPort "${port}"
            fi
        fi

    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        local updateFirewalldStatus=
        if ! firewall-cmd --list-ports --permanent | grep -qw "${port}/${type}"; then
            updateFirewalldStatus=true
            firewall-cmd --zone=public --add-port="${port}/${type}" --permanent
            firewall-cmd --zone=public --add-port="${port}/${type}" --permanent --add-rich-rule="rule family=ipv6"
            checkFirewalldAllowPort "${port}"
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            firewall-cmd --reload
        fi
    fi
}

# 添加新端口
addCorePort() {
	if [[ "${coreInstallType}" != "1" ]] && [[ "${coreInstallType}" != "3" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi
	echoContent skyBlue "\n功能 1/${totalProgress} : 添加新端口"
	echoContent yellow "# 只给TLS+VISION添加新端口，永远不会支持Reality(Reality只建议用443)\n"
	echoContent red "\n=============================================================="
	echoContent yellow "# 注意事项\n"
	echoContent yellow "支持批量添加"
	echoContent yellow "不影响默认端口的使用"
	echoContent yellow "查看账号时，只会展示默认端口的账号"
	echoContent yellow "不允许有特殊字符，注意逗号的格式"
	echoContent yellow "录入示例:2053,2083,2087\n"

	echoContent yellow "1.添加端口"
	echoContent yellow "2.删除端口"
	echoContent yellow "3.查看已添加端口"
	echoContent red "=============================================================="
	read -r -p "请选择:" selectNewPortType
	if [[ "${selectNewPortType}" == "1" ]]; then
		read -r -p "请输入端口号:" newPort

		if [[ -n "${newPort}" ]]; then

			while read -r port; do
				
				if [[ "${port}" == "${Port}" ]];then
					echoContent yellow "不能和默认端口相同"
					echoContent yellow "自动跳过该端口"
					continue
				fi

				rm -rf "$(find ${configPath}* | grep "${port}")"

				local fileName=
				fileName="${configPath}02_dokodemodoor_inbounds_${port}.json"

				# 开放端口
				allowPort "${port}"

				cat <<EOF >"${fileName}"
{
  "inbounds": [
	{
	  "listen": "0.0.0.0",
	  "port": ${port},
	  "protocol": "dokodemo-door",
	  "settings": {
		"address": "127.0.0.1",
		"port": ${Port},
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
	elif [[ "${selectNewPortType}" == "3" ]]; then
		find ${configPath} -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        exit 0
	fi
}


# manageUser 用户管理
manageUser() {
	if [[ -z "${coreInstallType}" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi
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

# 自定义uuid
customUUID() {
    read -r -p "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
    echo
    if [[ -z "${currentCustomUUID}" ]]; then
        currentCustomUUID=$(${ctlPath} uuid)
        echoContent yellow "uuid：${currentCustomUUID}\n"

    else
		if [[ -e "${configPath}${frontingType}.json" ]]; then
			jq -r -c '.inbounds[0].settings.clients[].id' ${configPath}${frontingType}.json | while read -r line; do
            	if [[ "${line}" == "${currentCustomUUID}" ]]; then
                	echo >/tmp/xray-agent
            	fi
        	done
		fi
		if [[ -e "${configPath}${RealityfrontingType}.json" ]]; then
        	jq -r -c '.inbounds[0].settings.clients[].id' ${configPath}${RealityfrontingType}.json | while read -r line; do
            	if [[ "${line}" == "${currentCustomUUID}" ]]; then
                	echo >/tmp/xray-agent
            	fi
        	done
		fi
        if [[ -f "/tmp/xray-agent" && -n $(cat /tmp/xray-agent) ]]; then
            echoContent red " ---> UUID不可重复"
            rm /tmp/xray-agent
            exit 0
        fi
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

    # 生成用户
    if [[ "${userNum}" == "1" ]]; then
        customUUID
    fi

    while [[ ${userNum} -gt 0 ]]; do
        local users=
        ((userNum--)) || true
        if [[ -n "${currentCustomUUID}" ]]; then
            uuid=${currentCustomUUID}
        else
            uuid=$(${ctlPath} uuid)
        fi

        users="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"alterId\":0}"

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

		if echo ${currentInstallProtocolType} | grep -q 7; then
            local vlessUsers="${users//\,\"alterId\":0/}"
            local vlessTcpResult
            vlessTcpResult=$(jq -r ".inbounds[0].settings.clients += [${vlessUsers}]" ${configPath}${RealityfrontingType}.json)
            echo "${vlessTcpResult}" | jq . >${configPath}${RealityfrontingType}.json
        fi

		if echo ${currentInstallProtocolType} | grep -q 8; then
            local vlessUsers="${users//xtls-rprx-vision/}"
			vlessUsers="${users//\,\"alterId\":0/}"
            local vlessTcpResult
            vlessTcpResult=$(jq -r ".inbounds[0].settings.clients += [${vlessUsers}]" ${configPath}08_VLESS_Reality_h2_inbounds.json)
            echo "${vlessTcpResult}" | jq . >${configPath}08_VLESS_Reality_h2_inbounds.json
        fi

    done

    reloadCore
    echoContent green " ---> 添加完成"
    manageAccount 1
}

# 移除用户
removeUser() {

	if [[ "${coreInstallType}" == "3" ]];then
		userIds=$(jq -r -c .inbounds[0].settings.clients[].id ${configPath}${frontingType}.json ${configPath}${RealityfrontingType}.json | sort | uniq)
	elif [[ "${coreInstallType}" == "2" ]];then
		userIds=$(jq -r -c .inbounds[0].settings.clients[].id ${configPath}${RealityfrontingType}.json | sort | uniq)
	elif [[ "${coreInstallType}" == "1" ]];then
		userIds=$(jq -r -c .inbounds[0].settings.clients[].id ${configPath}${frontingType}.json | sort | uniq)
	fi
	echo "${userIds}" | awk '{print NR""":"$0}'
	read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex

	mapfile -t userIdsArray <<< "${userIds}"
	
	if [[ -z ${userIdsArray[$((delUserIndex-1))]} ]]; then
    	echoContent red " ---> 选择错误"
	else
    	userIdToDelete=${userIdsArray[$((delUserIndex-1))]}
	fi
	
	if [[ -n "${delUserIndex}" ]]; then
		if echo ${currentInstallProtocolType} | grep -q 0; then
			local vlessTcpResult
			vlessTcpResult=$(jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' ${configPath}${frontingType}.json)
			echo "${vlessTcpResult}" | jq . >${configPath}${frontingType}.json
		fi
		
		if echo ${currentInstallProtocolType} | grep -q 1; then
			local vlessWSResult
			vlessWSResult=$(jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' ${configPath}03_VLESS_WS_inbounds.json)
			echo "${vlessWSResult}" | jq . >${configPath}03_VLESS_WS_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 2; then
			local trojangRPCUsers
			trojangRPCUsers=$(jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.password == $uid)))' ${configPath}04_trojan_gRPC_inbounds.json)
			echo "${trojangRPCUsers}" | jq . >${configPath}04_trojan_gRPC_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 3; then
			local vmessWSResult
			vmessWSResult=$(jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' ${configPath}05_VMess_WS_inbounds.json)
			echo "${vmessWSResult}" | jq . >${configPath}05_VMess_WS_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 5; then
			local vlessGRPCResult
			vlessGRPCResult=$(jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' ${configPath}06_VLESS_gRPC_inbounds.json)
			echo "${vlessGRPCResult}" | jq . >${configPath}06_VLESS_gRPC_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 4; then
			local trojanTCPResult
			trojanTCPResult=$(jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.password == $uid)))' ${configPath}04_trojan_TCP_inbounds.json)
			echo "${trojanTCPResult}" | jq . >${configPath}04_trojan_TCP_inbounds.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 7; then
			local vlessRealitytcpResult
			vlessRealitytcpResult=$(jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' ${configPath}${RealityfrontingType}.json)
			echo "${vlessRealitytcpResult}" | jq . >${configPath}${RealityfrontingType}.json
		fi

		if echo ${currentInstallProtocolType} | grep -q 8; then
			local vlessRealityh2Result
			vlessRealityh2Result=$(jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' ${configPath}08_VLESS_Reality_h2_inbounds.json)
			echo "${vlessRealityh2Result}" | jq . >${configPath}08_VLESS_Reality_h2_inbounds.json
		fi

		reloadCore
	fi
	manageAccount 1
}

# 更新脚本
updateXRayAgent() {
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
	if [[ -z "${coreInstallType}" ]]; then
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
			if [[ "${coreInstallType}" == "2" ]] || [[ "${coreInstallType}" == "3" ]]; then
				sed -i 's/"show": false/"show": true/' "${configfile}${RealityfrontingType}.json"
			fi
		elif [[ "${logStatus}" == "true" ]]; then
			cat <<EOF >${configPath}00_log.json
{
  "log": {
    "error": "${configPathLog}error.log",
    "loglevel": "warning"
  }
}
EOF
			if [[ "${coreInstallType}" == "2" ]] || [[ "${coreInstallType}" == "3" ]]; then
				sed -i 's/"show": true/"show": false/' "${configfile}${RealityfrontingType}.json"
			fi
		fi

		reloadCore
		checkLog 1
		;;
	2)
		tail -f "${configPathLog}"access.log
		;;
	3)
		tail -f "${configPathLog}"error.log
		;;
	4)
		tail -n 100 /etc/xray-agent/crontab_tls.log
		;;
	5)
		tail -n 100 /etc/xray-agent/tls/acme.log
		;;
	6)
		echo >"${configPathLog}"access.log
		echo >"${configPathLog}"error.log
		;;
	esac
}

warpRouting() {
	if [[ -z "${coreInstallType}" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi
	echoContent skyBlue "\n进度  $1/${totalProgress} : WARP分流"

	#检测WARP是否安装并开启
	if [[ "$(ip a)" =~ ": WARP:" ]]; then
		echoContent red " ---> 已安装，网卡名称为WARP"
		warpinterface="WARP"
	elif [[ "$(ip a)" =~ ": wgcf:" ]]; then
		echoContent red " ---> 已安装，网卡名称为wgcf"
		warpinterface="wgcf"
	else
		echoContent red " ---> 未安装或未开启，请使用脚本安装或开启"
		menu
		exit 0
	fi

	echoContent red "\n=============================================================="
	echoContent yellow "1.添加域名"
	echoContent yellow "2.卸载WARP分流"
	echoContent yellow "3.查看已分流域名"
	echoContent yellow "4.分流CN的域名和IP"
	echoContent yellow "5.卸载分流CN域名和IP"
	echoContent red "=============================================================="
	echoContent red "需要在warp一键脚本安装后，手动更改wgcf的配置，详情请见https://blog.suysker.xyz/archives/235"
	read -r -p "请选择:" warpStatus
	if [[ "${warpStatus}" == "3" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="warp-out")|.domain' ${configPath}09_routing.json | jq -r
        exit 0
	elif [[ "${warpStatus}" != "2" && "${warpStatus}" != "5" ]]; then
		echoContent red "\n=============================================================="
		echoContent yellow "# 注意事项\n"
		echoContent yellow "1.规则仅支持预定义域名列表[https://github.com/v2fly/domain-list-community]"
		echoContent yellow "3.warp支持IPV4和IPV6"

		if [[ "${warpStatus}" == "1" ]]; then
			unInstallOutbounds warp-out
			outbounds=$(jq -r ".outbounds += [{\"protocol\":\"freedom\",\"streamSettings\":{\"sockopt\":{\"interface\":\"${warpinterface}\"}},\"settings\":{\"domainStrategy\":\"UseIP\"},\"tag\":\"warp-out\"}]" ${configPath}10_ipv4_outbounds.json)
		elif [[ "${warpStatus}" == "4" ]]; then
			unInstallOutbounds cn-out
			outbounds=$(jq -r ".outbounds += [{\"protocol\":\"freedom\",\"streamSettings\":{\"sockopt\":{\"interface\":\"${warpinterface}\"}},\"settings\":{\"domainStrategy\":\"UseIP\"},\"tag\":\"cn-out\"}]" ${configPath}10_ipv4_outbounds.json)
		fi
		
		echo "${outbounds}" | jq . >${configPath}10_ipv4_outbounds.json

		if [[ "${warpStatus}" == "1" ]]; then
			echoContent yellow "4.如内核启动失败请检查域名后重新添加域名"
			echoContent yellow "5.不允许有特殊字符，注意逗号的格式"
			echoContent yellow "6.每次添加都是重新添加，不会保留上次域名"
			echoContent yellow "7.录入示例:openai,google,youtube,facebook\n"
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
		elif [[ "${warpStatus}" == "4" ]]; then
			if [[ -f "${configPath}09_routing.json" ]]; then
				unInstallRouting cn-out outboundTag
				routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"domain\":[\"geosite:cn\"],\"ip\":[\"geoip:cn\"],\"outboundTag\":\"cn-out\"}]" ${configPath}09_routing.json)

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
            	"geosite:cn"
            ],
			"ip": [
            	"geoip:cn"
            ],
            "outboundTag": "cn-out"
          }
        ]
  }
}
EOF
			fi
			unInstallRouting cn-blackhole outboundTag
			unInstallOutbounds cn-blackhole
		else
			echoContent red " ---> 选择错误"
			exit 0
		fi

		echoContent green " ---> 添加成功"

	elif [[ "${warpStatus}" == "2" ]]; then

		unInstallRouting warp-out outboundTag

		unInstallOutbounds warp-out

		echoContent green " ---> WARP分流卸载成功"
	elif [[ "${warpStatus}" == "5" ]]; then

		unInstallRouting cn-out outboundTag

		unInstallOutbounds cn-out

		echoContent green " ---> 分流CN卸载成功"
	else
		echoContent red " ---> 选择错误"
		exit 0
	fi
	reloadCore

}

# 阻止访问黑名单及中国大陆IP
blacklist() {
	if [[ -z "${coreInstallType}" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi
	echoContent skyBlue "\n功能 1/${totalProgress} : 阻止访问中国大陆IP"

	echoContent red "\n=============================================================="
    echoContent yellow "1.添加域名"
    echoContent yellow "2.删除黑名单"
    echoContent yellow "3.查看已屏蔽域名"
	echoContent yellow "4.启用阻止访问中国大陆IP"
	echoContent yellow "5.卸载阻止访问中国大陆IP"
	echoContent yellow "若不想阻止访问CN的IP，请使用warp分流功能"
	echoContent yellow "此处只阻止访问CN的IP，域名则不进行阻止"
	echoContent red "=============================================================="
	read -r -p "请选择:" blacklistStatus

    if [[ "${blacklistStatus}" == "3" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="blackhole-out")|.domain' ${configPath}09_routing.json | jq -r
        exit 0
    elif [[ "${blacklistStatus}" == "1" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.规则仅支持预定义域名列表[https://github.com/v2fly/domain-list-community]"
        echoContent yellow "2.详细文档[https://www.v2fly.org/config/routing.html]"
        echoContent yellow "3.如内核启动失败请检查域名后重新添加域名"
        echoContent yellow "4.不允许有特殊字符，注意逗号的格式"
        echoContent yellow "5.每次添加都是重新添加，不会保留上次域名"
        echoContent yellow "6.支持hysteria"
        echoContent yellow "7.录入示例:speedtest,facebook,cn\n"
        read -r -p "请按照上面示例录入域名:" domainList

        if [[ -f "${configPath}09_routing.json" ]]; then
            unInstallRouting blackhole-out outboundTag

            routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"domain\":[\"geosite:${domainList//,/\",\"geosite:}\"],\"outboundTag\":\"blackhole-out\"}]" ${configPath}09_routing.json)

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
            "outboundTag": "blackhole-out"
          }
        ]
  }
}
EOF
        fi

        echoContent green " ---> 添加成功"

    elif [[ "${blacklistStatus}" == "2" ]]; then

        unInstallRouting blackhole-out outboundTag

        echoContent green " ---> 域名黑名单删除成功"
	elif [[ "${blacklistStatus}" == "4" ]]; then
		if [[ -f "${configPath}09_routing.json" ]]; then
			unInstallRouting cn-blackhole outboundTag
			routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"ip\":[\"geoip:cn\"],\"outboundTag\":\"cn-blackhole\"}]" ${configPath}09_routing.json)

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
            "outboundTag": "cn-blackhole"
          }
        ]
  }
}
EOF
		fi
	
		unInstallOutbounds cn-blackhole

		outbounds=$(jq -r '.outbounds += [{"protocol":"blackhole","tag":"cn-blackhole"}]' ${configPath}10_ipv4_outbounds.json)

		echo "${outbounds}" | jq . >${configPath}10_ipv4_outbounds.json

		unInstallRouting cn-out outboundTag

		unInstallOutbounds cn-out

		echoContent green " ---> 添加成功"
	elif [[ "${blacklistStatus}" == "5" ]]; then
		unInstallRouting cn-blackhole outboundTag
		echoContent green " ---> 阻止访问中国大陆IP卸载成功"
	fi
	reloadCore
}

# ipv6 分流
ipv6Routing() {
	if [[ -z "${coreInstallType}" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi

	pingIPv6=$(ping6 -c 1 www.google.com | sed -n '1p' | sed 's/.*(//g;s/).*//g')

	if [[ -z "${pingIPv6}" ]]; then
		echoContent red " ---> 不支持ipv6"
		exit 0
	fi
	
	echoContent skyBlue "\n功能 1/${totalProgress} : IPv6分流"
	echoContent red "\n=============================================================="
	echoContent yellow "1.添加域名"
	echoContent yellow "2.卸载IPv6分流"
	echoContent yellow "3.查看已分流域名"
	echoContent yellow "4.全局IPv6优先"
	echoContent yellow "5.全局IPv4优先"
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
		echoContent yellow "6.录入示例:openai,google,youtube,facebook,cn\n"
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
		jq -r -c '.routing.rules[]|select (.outboundTag=="IPv6-out")|.domain' ${configPath}09_routing.json | jq -r
        exit 0
    elif [[ "${ipv6Status}" == "4" ]]; then

			unInstallOutbounds IPv4-out
			unInstallOutbounds IPv6-out
			unInstallOutbounds blackhole-out

			outbounds=$(jq -r '.outbounds = [{"protocol":"freedom","settings":{"domainStrategy":"UseIPv6"},"tag":"IPv6-out"},{"protocol":"freedom","settings":{"domainStrategy":"UseIPv4"},"tag":"IPv4-out"}] + .outbounds + [{"protocol":"blackhole","tag":"blackhole-out"}]' ${configPath}10_ipv4_outbounds.json)

			echo "${outbounds}" | jq . >${configPath}10_ipv4_outbounds.json
        
		echoContent green " ---> 全局IPv6优先"
       
    elif [[ "${ipv6Status}" == "5" ]]; then

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

manageSniffing() {
	if [[ -z "${coreInstallType}" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi
	
	echoContent skyBlue "\n功能 1/${totalProgress} : 流量嗅探管理"
	echoContent red "\n=============================================================="

	if [[ $(jq '.inbounds[0].sniffing.enabled' ${configPath}${frontingType}.json) ]]; then
		echoContent red "\n流量嗅探功能默认开启,关闭将会导致routing规则失效"
		echoContent yellow "1.关闭流量嗅探"
		
		if [[ $(jq '.inbounds[0].sniffing.routeOnly' ${configPath}${frontingType}.json) ]]; then
			echoContent yellow "3.关闭流量嗅探仅供路由"
		else
			echoContent red "\n流量嗅探仅供路由默认关闭，开启将会导致routing规则失效"
			echoContent yellow "4.开启流量嗅探仅供路由"
		fi
	else
		echoContent yellow "2.开启流量嗅探"
	fi
	read -r -p "请按照上面示例录入域名:" sniffingtype

	if [[ "${sniffingtype}" == "1" ]]; then
		find ${configPath} -name "*_inbounds.json" | while read -r configfile; do
			sed -i 's/"enabled": true/"enabled": false/' "${configfile}"
		done
	elif [[ "${sniffingtype}" == "2" ]]; then
		find ${configPath} -name "*_inbounds.json" | while read -r configfile; do
			sed -i 's/"enabled": false/"enabled": true/' "${configfile}"
		done
	elif [[ "${sniffingtype}" == "3" ]]; then
		find ${configPath} -name "*_inbounds.json" | while read -r configfile; do
			sed -i 's/"routeOnly": true/"routeOnly": false/' "${configfile}"
		done
	elif [[ "${sniffingtype}" == "4" ]]; then
		find ${configPath} -name "*_inbounds.json" | while read -r configfile; do
			sed -i 's/"routeOnly": false/"routeOnly": true/' "${configfile}"
		done
	else
		echoContent red " ---> 选择错误"
		exit 0
	fi

	reloadCore
}

# 删除证书
removeCert() {
    # 获取证书列表
    mapfile -t certificates < <(for certFile in /etc/xray-agent/tls/*.crt; do basename "$certFile" .crt; done)

    # 显示证书列表
    for i in "${!certificates[@]}"; do
        echo "$((i+1)): ${certificates[$i]}"
    done

    # 获取要删除的证书的索引
    read -r -p "请选择要删除的证书编号[仅支持单个删除]:" delCertificateIndex
    delCertificateIndex=$((delCertificateIndex - 1))

    # 检查索引是否有效
    if [[ ${delCertificateIndex} -lt 0 || ${delCertificateIndex} -ge ${#certificates[@]} ]]; then
        echoContent red " ---> 选择错误"
    else
        # 删除对应的证书文件
        sudo rm -f "/etc/xray-agent/tls/${certificates[$delCertificateIndex]}.crt" "/etc/xray-agent/tls/${certificates[$delCertificateIndex]}.key"
        echoContent green " ---> 证书已删除"
    fi
}


manageCert() {
	if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		exit 0
	fi
	echoContent skyBlue "\n功能 1/${totalProgress} : 证书管理"
	echoContent red "\n=============================================================="
	echoContent yellow "# 可以申请其他证书\n"
	echoContent yellow "1.申请证书"
	echoContent yellow "2.更新证书"
	echoContent yellow "3.删除证书"
	echoContent red "=============================================================="
	read -r -p "请输入:" manageCertStatus
	if [[ "${manageCertStatus}" == "1" ]]; then
		echo
		echoContent yellow "请输入要申请证书的域名 例: www.xray-agent.com --->"
		read -r -p "域名:" domain
		installTLS 1 0
		installCronTLS 1
	elif [[ "${manageCertStatus}" == "2" ]]; then
		renewalTLS "all"
	elif [[ "${manageCertStatus}" == "3" ]]; then
		removeCert
	else
		echoContent red " ---> 选择错误"
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
	installTLS 3 0
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

	auto_update_geodata
	# 生成账号
	checkGFWStatue 10
	showAccounts 11
}

# xray-core 安装
xrayCoreInstall_Reality() {

	totalProgress=7
	installTools 1

	handleXray stop
	
	# 安装Xray
	installXray 2
	installXrayService 3

	initTLSRealityConfig 4

	initXrayRealityConfig 5
	
	handleXray stop
	sleep 2
	handleXray start

	auto_update_geodata
	# 生成账号
	checkGFWStatue 6
	showAccounts 7
}

# 账号管理
manageAccount() {
	if [[ -z "${coreInstallType}" ]]; then
		echoContent red " ---> 未安装，请使用脚本安装"
		menu
		exit 0
	fi
	echoContent skyBlue "\n功能 1/${totalProgress} : 账号管理"
	echoContent red "\n=============================================================="
	echoContent yellow "# 每次删除、添加账号后，需要重新查看订阅生成订阅\n"
	echoContent yellow "1.查看账号"
	echoContent yellow "2.添加用户"
	echoContent yellow "3.删除用户"
	echoContent red "=============================================================="
	read -r -p "请输入:" manageAccountStatus
	if [[ "${manageAccountStatus}" == "1" ]]; then
		showAccounts 1
	elif [[ "${manageAccountStatus}" == "2" ]]; then
		addUser
	elif [[ "${manageAccountStatus}" == "3" ]]; then
		removeUser
	else
		echoContent red " ---> 选择错误"
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

	if [[ -n "${coreInstallType}" ]]; then
		handleXray stop
		rm -rf /etc/systemd/system/xray.service
		echoContent green " ---> 删除Xray开机自启完成"
	fi

	rm -rf /etc/xray-agent
	rm -rf ${nginxConfigPath}alone.conf

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
	
	if [[ "${xrayCoreCPUVendor}" == "Xray-linux-64" ]]; then
		adgCoreCPUVendor="AdGuardHome_linux_amd64"
	elif [[ "${xrayCoreCPUVendor}" == "Xray-linux-arm64-v8a" ]]; then
		adgCoreCPUVendor="AdGuardHome_linux_arm64"
	fi
	
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
		wget -O '/tmp/AdGuardHome_linux_amd64.tar.gz' "https://static.adguard.com/adguardhome/release/${adgCoreCPUVendor}.tar.gz"
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
	echoContent green "当前版本:v2.9.0"
	echoContent green "Github:https://github.com/mack-a/xray-agent"
	echoContent green "描述:八合一共存脚本\c"
	showInstallStatus
	echoContent red "\n=============================================================="
	if [[ "${coreInstallType}" == "1" ]] || [[ "${coreInstallType}" == "3" ]] ; then
		echoContent yellow "1.重新安装TLS+Vison"
	else
		echoContent yellow "1.安装TLS+Vison"
	fi
	if [[ "${coreInstallType}" == "2" ]] || [[ "${coreInstallType}" == "3" ]] ; then
		echoContent yellow "2.重新安装Reality+Vison"
	else
		echoContent yellow "2.安装Reality+Vison"
	fi
	echoContent skyBlue "-------------------------工具管理-----------------------------"
	echoContent yellow "3.账号管理"
	echoContent yellow "4.更换伪装站"
	echoContent yellow "5.证书管理"
	echoContent yellow "6.IPv6分流"
	echoContent yellow "7.阻止访问黑名单及中国大陆IP"
	echoContent yellow "8.WARP分流及中国大陆域名+IP"
	echoContent yellow "9.添加新端口"
	echoContent yellow "10.流量嗅探管理"
	echoContent skyBlue "-------------------------版本管理-----------------------------"
	echoContent yellow "11.core管理"
	echoContent yellow "12.更新脚本"
	echoContent skyBlue "-------------------------脚本管理-----------------------------"
	echoContent yellow "13.查看日志"
	echoContent yellow "14.卸载脚本"
	echoContent skyBlue "-------------------------其他功能-----------------------------"
	echoContent yellow "15.Adguardhome"
	echoContent yellow "16.WARP"
	echoContent yellow "17.内核管理及BBR优化"
	echoContent yellow "18.Hysteria一键"
	echoContent red "=============================================================="
	mkdirTools
	aliasInstall
	read -r -p "请选择:" selectInstallType
	case ${selectInstallType} in
	1)
		xrayCoreInstall
		;;
	2)
		xrayCoreInstall_Reality
		;;
	3)
		manageAccount 1
		;;
	4)
		updateNginxBlog 1
		;;
	5)
		manageCert 1
		;;
	6)
		ipv6Routing 1
		;;
	7)
		blacklist 1
		;;
	8)
		warpRouting 1
		;;
	9)
		addCorePort 1
		;;
	10)
		manageSniffing 1
		;;
	11)
		xrayVersionManageMenu 1
		;;
	12)
		updateXRayAgent 1
		;;
	13)
		checkLog 1
		;;
	14)
		unInstall 1
		;;
	15)
		AdguardManageMenu 1
		;;
	16)
		wget -N https://raw.githubusercontent.com/fscarmen/warp/main/warp-go.sh && bash warp-go.sh
		;;
	17)
		wget -N https://raw.githubusercontent.com/jinwyp/one_click_script/master/install_kernel.sh && bash install_kernel.sh
		;;
	18)
		bash <(curl -fsSL https://git.io/hysteria.sh)
		;;
	esac
}
# -------------------------------------------------------------
#初始化变量
initVar
#检查系统类型
checkSystem
#检查CPU架构
checkCPUVendor
#检查XRAY是否安装完成
readInstallType
#读取安装协议类型
readInstallProtocolType
#读取伪装站点域名、UUID及路径
readConfigHostPathUUID
#检查宝塔面板
checkBTPanel

# -------------------------------------------------------------
if [[ "$1" == "RenewTLS" ]]; then
	renewalTLS "all"
	exit 0
fi
menu
