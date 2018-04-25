#!/bin/bash


function Log() {
    local level=$2
    local msg=$1
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    case ${level} in
        info|INFO)
            level="\033[44;37;1m INFO \033[0m"
            ;;
        warn|WARN)
            level="\033[44;32;1m WARN \033[0m"
            ;;
        error|ERROR)
            level="\033[44;31;5m ERROR \033[0m"
            ;;
        *)
            level="\033[44;37;1m INFO \033[0m"
            ;;
        esac
    echo -e "[${timestamp}] ${level}: ${msg}"
    return 0
}

function decompress_pkg() {
    local pkg_path=$1
    local target_path="/tmp"

    if [ ! -f "${pkg_path}" -o ! -d "${target_path}" ]
        then
        Log "文件 ${pkg_path} 或者目录 ${target_path} 不存在。" "error"
        return 1
    fi
    local ext=${pkg_path##*.}
    Log "开始解压文件 ${pkg_path}。"
    case ${ext} in
        tar|gz|bz2)
            tar -xf ${pkg_path} -C ${target_path}
            ;;
        zip)
            unzip -o ${pkg_path} -d ${target_path} &> /dev/null
            ;;
        *)
            Log "不支持文件 ${pkg_path} 所指定的解压类型 ${ext}。" "error"
            return 1
            ;;
    esac
    Log "解压文件 ${pkg_path} 成功。"
    return 0
}


function compile_install() {
    local compile_path=$1
    local ins_path=$2
    local compile_args=$3
    local tmp_ret=0

    cd ${compile_path} &> /dev/null
    Log "切换目录到${compile_path},开始编译安装。编译参数为：${compile_args}"

    if [ -f "autogen.sh" ]
        then
        ./autogen.sh &> install.log || tmp_ret=1
    fi
    if [ "${tmp_ret}" == "0" ]
        then
        ./configure --prefix=${ins_path} ${compile_args} &>> install.log || tmp_ret=1
    fi
    if [ "${tmp_ret}" == "0" ]
        then
        make &>> install.log || tmp_ret=1
    fi
    if [ "${tmp_ret}" == "0" ]
        then
        make install &>> install.log || tmp_ret=1
    fi
    if [ "${tmp_ret}" != "0" ]
        then
        Log "编译安装失败，中断操作,详情请见日志文件 ${compile_path}/install.log。" "error"
        return ${tmp_ret}
    fi

    Log "编译安装成功。"

    return ${tmp_ret}
}

function yum_install () {
    local ins_name=$1
    local is_must=$2
    local tmp_ret=0

    if [ "${is_must}" == "" ]
        then
        is_must=false
    else
        is_must=true
    fi

    Log "开始使用 yum 安装 ${ins_name}。"
    yum install -y ${ins_name} &>> /tmp/install.log || tmp_ret=1
    if [ ${tmp_ret} != "0" ]
        then
        if ${is_must}
            then
            Log "Yum 安装 ${ins_name} 失败, 详细日志请见 /tmp/install.log。" "error"
            return 1
        else
            Log "Yum 安装 ${ins_name} 失败, 详细日志请见 /tmp/install.log。" "warn"
        fi
    fi
    Log "Yum 安装 ${ins_name}成功。"
    return 0
}

function clean_dir() {
    local target_path=$1
    local tmp_ret=0

    if [ ! -e "${target_path}" ]
        then
        Log "目标路径 ${target_path} 不存在。" "warn"
        return 1
    fi
    rm -rf ${target_path}  &> /dev/null  || tmp_ret=1
    if [ "${tmp_ret}" != "0" ]
        then
        Log "删除路径 ${target_path} 失败。" "warn"
        return ${tmp_ret}
    fi
    return 0

}

function main() {
    local is_server=$1
    if [ "${is_server}" != "" ]
        then
        is_server=true
    else
        is_server=false
    fi

    for ele in python-devel/1 texinfo/1 openssl/1 openssl-devel/1 libssh2/1 libssh2-devel/1 libxml2/1 libxml2-devel/1 libevent/1 libevent-devel/1 curl/1 libcurl/1 libcurl-devel/1 net-snmp-devel/1
    do
        ins_name=${ele%/*}
        is_must=${ele#*/}
        yum_install ${ins_name} ${is_must} || return $?
    done

    decompress_pkg "/tmp/zabbix-3.4.7.tar.gz" || return $?
    decompress_pkg "/tmp/iksemel-master.zip" || return $?
    decompress_pkg "/tmp/pcre-8.39.tar.gz" || return $?

    compile_install "/tmp/iksemel-master" "/usr/local" "" || return $?
    compile_install "/tmp/pcre-8.39" "/usr/local/pcre" "" || return $?

    compile_args="--enable-agent --with-net-snmp --with-libcurl --with-libxml2 --enable-ipv6 --with-ssh2 --with-iconv --with-openssl --with-libpcre=/usr/local/pcre"
    if ${is_server}
        then
        compile_args="--enable-server --enable-agent --with-mysql --with-net-snmp --with-libcurl --with-libxml2 --enable-ipv6 --with-ssh2 --with-iconv --with-openssl --with-libpcre=/usr/local/pcre"
    fi

    compile_install "/tmp/zabbix-3.4.7" "/usr/local/zabbix" "${compile_args}" || return $?

    clean_dir "/tmp/zabbix-3.4.7.tar.gz"
    clean_dir "/tmp/iksemel-master.zip"
    clean_dir "/tmp/iksemel-master"
    if ! ${is_server}
        then
        clean_dir "/tmp/zabbix-3.4.7"
    fi

    return 0
}

Log "开始执行脚本 $0" 
main
MAIN_RET=$?

if [ "${MAIN_RET}" != "0" ]
    then
    Log "脚本 $0 执行失败。" "error"
else
    Log "脚本 $0 执行成功。" "info"    
fi

exit ${MAIN_RET}