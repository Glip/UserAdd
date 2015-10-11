#!/bin/bash
######################## SETUP ############################################################
 
IP_ADDRESS="ip"
HOST_NAME="hostname"
MYSQL_PASS="mysqlpass"
 
############################################################################################
 
APACHE2_DIR="/etc/apache2"
APACHE2_SAVL_DIR="$APACHE2_DIR/sites-available"
APACHE2_SENBL_DIR="$APACHE2_DIR/sites-enabled"
 
UID_ROOT=0
  
if [ "$UID" -ne "$UID_ROOT" ]; then
  echo "$0 - Requires root privileges"
  exit 1
fi
 
function is_file(){
    local f="$1"
    [[ -f "$f" ]] && return 0 || return 1
}
 
function is_dir(){
    local d="$1"
    [[ -d "$d" ]] && return 0 || return 1
}
 
function is_exits(){
    local check="$1"
    if (is_file "$check") then
 return 0
    fi
    if (is_dir "$check") then
 return 0
    fi
    return 1 #false
}
 
function is_user(){
    local check_user="$1";
    grep "$check_user:" /etc/passwd >/dev/null
    if [ $? -ne 0 ]; then
 #echo "NOT HAVE USER"
 return 1
    else
 #echo "HAVE USER"
 return 0
    fi
}
 
#function create_user_website(){
#    cat <<eof >> outfile.txt
#Text file content
#EOF
#}
 
function generate_pass(){
    CHARS="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!@#%^&*()-_=+"
    LENGTH="12"
    while [ "${n:=1}" -le "$LENGTH" ] ; do
 PASSWORD="$PASSWORD${CHARS:$(($RANDOM%${#CHARS})):1}"
        let n+=1
    done
    echo $PASSWORD
}
 
function is_yes(){
#TODO - add check 3-rd parameter for set default ansver (if press enter)
    while true
    do
 echo -n "Yes or No[Y/n]:"
 read  x
 if [ -z "$x" ]
 then
     return 0; #defaul answer: Yes
 fi
 case "$x" in
 y |Y |yes |Д |д |да ) return 0;;
 n |N |no |Н |н |нет ) return 1;;
# * ) ; # asc again
 esac
    done
}
 
function is_installed(){
#    local I=`dpkg -s $1 | grep "Status"`
    local out=`dpkg --status $1 | grep Status:`
    #echo "$out"
    if [ -n "$out" ]
    then
 echo $1" installed"
 return 0
    else
 echo $1" not installed"
 return 1
    fi
}
 
function is_running(){
    local result="$(ps -A|grep $1|wc -l)"
    if [[ $result -eq 0 ]]; then
 return 1
    else
 return 0
    fi
}
 
function create_user(){
    local login="$1"
    local password="$2"
    `useradd -d /web/$login -m -s /usr/sbin/nologin $login`
    #set password
    echo -e "$password\n$password\n" | passwd $login >> /dev/null
}
function delete_user(){
    local login=$1
    `userdel -r $login`
    # remove virtual host
    rm $APACHE2_DIR/sites-enabled/$USER_NAME
    rm $APACHE2_DIR/sites-available/$USER_NAME
    # remove database
    mysql -uroot -p${MYSQL_PASS} --execute="drop database ${USER_NAME};"
    # remove user
    mysql -uroot -p${MYSQL_PASS} --execute="DROP USER '${USER_NAME}'@'localhost';"
}
 
#echo "paremeters count: $#"
 
if [ $# -lt 1 ]; then # >=
    echo "USAGE: sudo add_new_user.sh <user_name> [delete]"
    echo "       - add system user <user_name>, create user folder, create virtual host <user_name>.${HOST_NAME}, create mysql"
    echo "    user and database named <user_name>"
    echo "       - delete - for remove user from system (system user and user folder, apache virtual host and mysql user and database)"
    exit;
fi;
 
USER_NAME=$1
 
if [ $# -eq 2 ]; then
    if [ "$2" == "delete" ]; then
 echo "delete user \"$1\""
 delete_user $USER_NAME
    else
 echo "unknown parameter $2"
    fi
    exit;
fi;
 
echo -n "Check user name $USER_NAME: "
if( is_user "$USER_NAME" )then
    echo "ERROR: Already exits"
    exit;
else
    echo "OK"
fi
 
echo -n "Check Apache2: "
if(is_dir "$APACHE2") then
    echo "not found directory $APACHE2_DIR"
    echo "Apache not installed?"
    exit;
else
    echo "OK"
fi
 
#check installing mysql
#is_installed apache2
#is_installed php5
#is_installed mysql-server
#is_running mysqld
echo -n "Check MySQL status: "
if(is_running mysqld)then
    echo "OK [Running]";
else
    echo "Error: need start mysql daemon!"
    exit
fi
 
USER_PASSWORD="$(generate_pass)"
 
echo "-----------------------------------"
echo "User name    : $USER_NAME"
echo "User password: $USER_PASSWORD"
echo "-----------------------------------"
echo -n "Continue? "
if(! is_yes) then
    exit;
fi
 
echo "--- create user ---"
create_user "$USER_NAME" "$USER_PASSWORD"
echo "--- create web site ---"
`mkdir /web/$USER_NAME/htdocs`
`mkdir /web/$USER_NAME/logs`  #in future save log for current user
`chown $USER_NAME:$USER_NAME /web/$USER_NAME/htdocs`
 
virual_host_data="
<virtualhost *:80>
 ServerName ${USER_NAME}.${HOST_NAME}
        ServerAlias www.${USER_NAME}.${HOST_NAME}
        ServerAdmin webmaster@${USER_NAME}.${HOST_NAME}
        DocumentRoot /web/${USER_NAME}/htdocs
        <directory /web/${USER_NAME}/>
                Options Indexes FollowSymLinks MultiViews
                AllowOverride All
                Order allow,deny
                allow from all
        </Directory>
		AssignUserId www-data ${USER_NAME}
 
        ScriptAlias /cgi-bin/ /web/${USER_NAME}/cgi-bin/
        <directory "/web/${USER_NAME}/cgi-bin">
                AllowOverride All
                Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
                Order allow,deny
                Allow from all
        </Directory>
 
        ErrorLog /web/${USER_NAME}/logs/${USER_NAME}.${HOST_NAME}.error.log
        LogLevel warn
        CustomLog /web/${USER_NAME}/logs/${USER_NAME}.${HOST_NAME}.access.log combined
		# open_basedirдля домашней директории пользователя, можно добавить несколько директорий при необходимости, директории разделяются двоеточием .:.
		php_admin_value open_basedir "/web/${USER_NAME}/"
		# Включаем сейф-мод, я сделал это в каждом конфиге сайта для удобства отключения при необходимости.
		php_admin_value safe_mode "on"
		# Определяем нашу временную директорию как основную, вместо /tmp и устанавливаем её директорией для хранения сессий.
		php_admin_value upload_tmp_dir "/web/${USER_NAME}/tmp"
		php_admin_value session.save_path "/web/${USER_NAME}/tmp"	
</VirtualHost>
"
touch ${APACHE2_DIR}/sites-available/${USER_NAME}
echo "$virual_host_data" >> ${APACHE2_DIR}/sites-available/${USER_NAME}
#add link
`ln -s ${APACHE2_DIR}/sites-available/${USER_NAME} ${APACHE2_DIR}/sites-enabled/${USER_NAME}`
#create default html
touch /web/${USER_NAME}/htdocs/index.html
echo "<header><title>${USER_NAME}</title></header><h1>It's Working!</h1>" >> /web/${USER_NAME}/htdocs/index.html
#add in hosts
#echo "${IP_ADDRESS} ${USER_NAME}.${HOST_NAME}" >> /etc/hosts 
 
echo "--- create database and mysql user ---"
    mysql -uroot -p${MYSQL_PASS} --execute="create database ${USER_NAME};"
    mysql -uroot -p${MYSQL_PASS} --execute="GRANT ALL PRIVILEGES ON ${USER_NAME}.* TO '${USER_NAME}'@'localhost' IDENTIFIED by '${USER_PASSWORD}'  WITH GRANT OPTION;"
echo "--- show hosting information ---"
 
#display information
echo "*****************************************"
echo "* Web Site: ${USER_NAME}.${HOST_NAME}"
echo "* user: ${USER_NAME}"
echo "* password: ${USER_PASSWORD}"
echo "*"
echo "* Server: ${IP_ADDRESS}"
echo "* ftp user: ${USER_NAME}"
echo "* ftp password: ${USER_PASSWORD}"
echo "*"
echo "* mysql server: ${IP_ADDRESS}"
echo "* mysql db_name: ${USER_NAME}"
echo "* mysql user: ${USER_NAME}"
echo "* mysql password: ${USER_PASSWORD}"
echo "*****************************************"
echo -n "Do you want install WordPress? "
if(! is_yes) then
    exit;
fi
	wget -P /web/${USER_NAME}/htdocs https://ru.wordpress.org/latest-ru_RU.zip
	unzip /web/${USER_NAME}/htdocs/latest-ru_RU.zip -d /web/${USER_NAME}/htdocs/
	rm /web/${USER_NAME}/htdocs/latest-ru_RU.zip
	mv /web/${USER_NAME}/htdocs/wordpress/* /web/${USER_NAME}/htdocs/
	rm -R /web/${USER_NAME}/htdocs/wordpress
	rm /web/${USER_NAME}/htdocs/index.html
	chown ${USER_NAME}:${USER_NAME} -R /web/${USER_NAME}

echo "*****************************************"
echo "* Web Site: ${USER_NAME}.${HOST_NAME}"
echo "* user: ${USER_NAME}"
echo "* password: ${USER_PASSWORD}"
echo "*"
echo "* Server: ${IP_ADDRESS}"
echo "* ftp user: ${USER_NAME}"
echo "* ftp password: ${USER_PASSWORD}"
echo "*"
echo "* mysql server: ${IP_ADDRESS}"
echo "* mysql db_name: ${USER_NAME}"
echo "* mysql user: ${USER_NAME}"
echo "* mysql password: ${USER_PASSWORD}"
echo "*****************************************"
