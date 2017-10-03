#!/bin/bash

MAINPATH="/var/workspace"
GITPATH="/home/gitrepo/workspace.git/"
HOOKPATH="${GITPATH}hooks/post-receive"
#本机项目发布路径
SRCPATH="${MAINPATH}/php_api/"
IP="123.56.10.199"
PRODPATH="${IP}:${MAINPATH}/php_api/"

EXCLUDEFILENAME="exclude-list.txt"
EXCLUDEFILEPATH="${MAINPATH}${EXCLUDEFILENAME}"

if [[ ! -d "${GITPATH}" ]]; then
	mkdir -p "${GITPATH}"
	cd "${GITPATH}"
	git init --bare
	echo "- [${PROJID}] GIT Repository is initialized"
	touch "${HOOKPATH}"
	chmod +x "${HOOKPATH}"
	echo "#!/bin/sh" >> "${HOOKPATH}"
	echo "GIT_DIR='${SRCPATH}.git'" >> "${HOOKPATH}"
	echo "GIT_WORK_TREE='${SRCPATH}'" >> "${HOOKPATH}"
	echo "cd ${MAINPATH}" >> "${HOOKPATH}"
	echo "/bin/bash ${MAINPATH}deploy.sh" >> "${HOOKPATH}"
fi

# 创建本机项目发布的文件
cd "${MAINPATH}"
if [[ ! -d "${SRCPATH}" ]]; then
	git clone "${GITPATH}" src
	echo "- Source folder is initialized"
fi

# 创建排除文件列表
cd "${MAINPATH}"
if [[ ! -f "${EXCLUDEFILEPATH}" ]]; then
	touch "${EXCLUDEFILEPATH}"
	echo ".git" >> "${EXCLUDEFILEPATH}"
	echo ".gitignore" >> "${EXCLUDEFILEPATH}"
	echo ".gitmodules" >> "${EXCLUDEFILEPATH}"
	echo "- Exclude file is initialized"
fi

# 拉取最新的项目文件
cd "${SRCPATH}"
git pull
echo "- Latest project files are pulled"

cd "${MAINPATH}"
rsync -ruvp --exclude-from "${EXCLUDEFILENAME}" "${SRCPATH}" "${PRODPATH}"