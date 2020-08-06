# crystaldrive

A file manager that uses [Crystalstore](https://github.com/crystaluniverse/crystalstore) as a virtual file system
Crystaldrive is based on [Filebrowser](https://filebrowser.org/)

## Build ui

First time run `./build.sh -u` to install all frontend dependencies & build UI
later on just run `./build.sh -f` to build frontend files only

## build script
```
./build.sh 
usage: ./build -u --ui (Install all dependencies and build ui
       ./build -a --all (Fully install UI requirements, build UI and build server binaries)
       ./build -f --front (Only build frontend code no dependencies will be installed)

```

# Make sure onlyoffice document server is running
```
docker run -i -t -d -p 80:80 -v /home/hamdy/onlyoffice/data:/var/www/onlyoffice/Data onlyoffice/documentserver
```

## Run
```
shards install

```

```
export JWT_SECRET_KEY="{blah}" # for jwt tokens
export SESSION_SECRET_KEY="{blah}"
export SEED="sY4dAEWZXsPQEMOHzP65hNeDr4+7D0D6fbEm2In22t0="  # 3botlogin seed
export OPEN_KYC_URL=https://openkyc.live/verification/verify-sei
export THREEBOT_LOGIN_URL=https://login.threefold.me
export ONLY_OFFICE_DATA_PATH=/home/hamdy/onlyoffice/data
export ONLY_OFFICE_HOST=127.0.0.1
```

```
crystal  run src/crystaldrive.cr
```
