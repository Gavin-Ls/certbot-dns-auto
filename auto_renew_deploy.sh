#!/bin/bash
# @author liu
# @time 2021-09-01
date >> /var/log/certbot.log
certbot renew --manual-auth-hook ./bootstrap.py >> /var/log/certbot.log
# 泛域名列表(需要保持最终部署到Nginx下的证书名称和泛域名对应关系。例如：abc.cn为域名，则公钥为abc.cn.pem。私钥为abc.cn.privkey.pem，生成的证书会部署到所有服务器)
domain_names=(abc.cn fat.abc.cn)

# 需要部署的服务器列表和证书目录
declare -A certIpAddrs
certIpAddrs=([192.168.0.101]="/data/software/openresty/nginx/ssl/" [192.168.0.102]="/data/software/openresty/nginx/ssl/")
# 部署证书需要的账号(需要设置免密登录，即通过ssh公钥进行登录，所有服务器必须有相同的Linux用户)
server_account=tomcat

# certbot生成的证书目录
cert_root_dir=/etc/letsencrypt/live/
# 证书保存的临时目录
cert_domain_name_tmp=/opt/certbot-manual-dns/domain_name/

# 证书公钥名称
publicKeyName=fullchain.pem
# 证书私钥名称
privkeyName=privkey.pem

# 证书正式部署
deployCert(){
        for ip in ${!certIpAddrs[*]};do
                # 部署证书文件($1为公钥，$2为私钥)
                rsync $1 $2 $server_account@$ip:${certIpAddrs[$ip]}
                # 重新加载Nginx配置
                ssh $server_account@$ip "sudo /data/software/openresty/nginx/sbin/nginx -s reload"
        done
}

for domain_name in ${domain_names[*]};do
        # 公钥证书(最新公钥)
        fullchain_pem="$cert_root_dir$domain_name/$publicKeyName"
        # 私钥证书(最新私钥)
        privkey_pem="$cert_root_dir$domain_name/$privkeyName"
        
        # 存放证书的临时目录(根据域名区分目录)
        cert_domain_name_child_tmp="$cert_domain_name_tmp$domain_name"
        if [ ! -d ${cert_domain_name_child_tmp} ]; then
                mkdir -p $cert_domain_name_child_tmp
        fi

        # 临时公钥证书文件(历史公钥)
        fullchain_pem_tmp="$cert_domain_name_child_tmp/$publicKeyName"
        if [ ! -f ${fullchain_pem_tmp} ]; then
                touch $fullchain_pem_tmp
        fi

        # 临时私钥证书文件(历史私钥)
        privkey_pem_tmp="$cert_domain_name_child_tmp/$privkeyName"
        if [ ! -f ${privkey_pem_tmp} ]; then
                touch $privkey_pem_tmp
        fi
        #部署标记(0-表示不需要部署，1-表示需要部署)。其中公钥和私钥只要有任意一个变化，即部署公钥和私钥
        deployFlag=0
        # 公钥证书内容 MD5值(最新公钥)
        fullchain_pem_md5=`md5sum $fullchain_pem | awk '{print $1}'`
        # 临时公钥证书内容 MD5值(历史公钥)
        fullchain_pem_tmp_md5=`md5sum $fullchain_pem_tmp | awk '{print $1}'`

        # 重命名后的公钥文件
        real_public_key="$cert_domain_name_child_tmp/$domain_name.pem"
        if [ $fullchain_pem_md5 != $fullchain_pem_tmp_md5 ]; then
                # copy新的公钥证书
                cat $fullchain_pem > $fullchain_pem_tmp
                # 重命名证书,并保留原始证书
                cp $fullchain_pem_tmp $real_public_key
                deployFlay=1
        fi
        # 私钥证书内容 MD5值(最新私钥)
        privkey_pem_md5=`md5sum $privkey_pem | awk '{print $1}'`
        # 临时私钥证书内容 MD5值(历史私钥)
        privkey_pem_tmp_md5=`md5sum $privkey_pem_tmp | awk '{print $1}'`

        # 重命名后的私钥文件
        real_privkey="$cert_domain_name_child_tmp/$domain_name.privkey.pem"
        if [ $privkey_pem_md5 != $privkey_pem_tmp_md5 ]; then
                # copy新的私钥证书
                cat $privkey_pem > $privkey_pem_tmp
                # 重命名证书,并保留原始证书
                cp $privkey_pem_tmp $real_privkey
                deployFlay=1
        fi
        # 判断是否部署证书(如果证书有变化则部署，否则不部署！)
        if [ $deployFlag == 1 ]; then
                # 证书部署调度
                deployCert $real_public_key $real_privkey
        fi
done
