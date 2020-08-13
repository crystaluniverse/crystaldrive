#!/bin/bash

FULL_UI=0
ALL=0
UI=0

usage()
{
    echo "usage: ./build -u --ui (Install all dependencies and build ui"
    echo "       ./build -a --all (Fully install UI requirements, build UI and build server binaries)"
    echo "       ./build -f --front (Only build frontend code no dependencies will be installed)"
}


while [ "$1" != "" ]; do
    case $1 in
        -u| --ui )              FULL_UI=1
                                ;;
        -f | --front )          UI=1
                                ;;
	-a | --all )            ALL=1
				;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

install_front_deps()
{
	clone_ui_repo
	pushd .
        cd frontend/frontend
	npm install
	popd
}

build_ui()
{
	clone_ui_repo
	pushd .
	cd frontend/frontend
	sed -i 's/'"'"'\[{\[ .StaticURL \]}\]/'"'"'\/static/g' vue.config.js
	npm run build
	popd
	rm -rf public
	mkdir -p public
	cp -r frontend/frontend/dist public/static
}

build_binary()
{
	clone_ui_repo
	shards install;
	crystal build src/crystaldrive.cr
}

clone_ui_repo()
{
	if [ ! -d frontend ]; then
    		echo "frontend dir is missing cloning UI code from git@github.com:crystaluniverse/crystaldrive-ui.git"
		git clone git@github.com:crystaluniverse/crystaldrive-ui.git frontend 
	fi
}

if [ "$UI" = "1" ]; then
	echo "Building UI files only"
	build_ui
	exit 0
fi

if [ "$FULL_UI" = "1" ]; then
        echo "Building UI"
	install_front_deps
        build_ui
	exit 0
fi

if [ "$ALL" = "1" ]; then
        echo "Building Everything"
        install_front_deps
        build_ui
	build_binary
	exit 0
fi

usage

