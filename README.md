![release](https://github.com/tgedr/bashutils/workflows/release/badge.svg?branch=master)
# bashutils
bash scripting utils include file

## Notes

the script tries to include variables and secrets through the files `variables.inc` and `secrets.inc` in its folder:
```
if [ ! -f "$this_folder/variables.inc" ]; then
  warn "we DON'T have a 'variables.inc' file"
else
  . "$this_folder/variables.inc"
fi

if [ ! -f "$this_folder/secrets.inc" ]; then
  warn "we DON'T have a 'secrets.inc' file"
else
  . "$this_folder/secrets.inc"
fi
``` 

...this environment loading procedure can be extended if one provides the following environment variables:
- `ADDITIONAL_VARIABLES` - the location of a file with additional environment variables to be sourced;
- `ADDITIONAL_SECRETS` - the location of a file with additional secrets to be sourced;
```
if [ ! -z "$ADDITIONAL_VARIABLES" ]; then
  debug "loading ADDITIONAL_VARIABLES"
  . "$ADDITIONAL_VARIABLES"
fi

if [ ! -z "$ADDITIONAL_SECRETS" ]; then
  debug "loading ADDITIONAL_SECRETS"
  . "$ADDITIONAL_SECRETS"
fi
```

## usage

...one can include a script snippet to retrieve and source `bashutils.inc` dynamically, 
so that it gets downloaded each time, or we can add a function in our scripts to 
update it whenever we need.

- add the include section in your bash script to get `bashutils.inc` dynamically
```
#!/usr/bin/env bash

# http://bash.cumulonim.biz/NullGlob.html
shopt -s nullglob

this_folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ -z "$this_folder" ]; then
  this_folder=$(dirname $(readlink -f $0))
fi
parent_folder=$(dirname "$this_folder")

# --- START include bashutils SECTION ---
_pwd=$(pwd)
cd "$this_folder"
curl -s https://api.github.com/repos/tgedr/bashutils/releases/latest \
| grep "browser_download_url.*utils\.tar\.bz2" \
| cut -d '"' -f 4 | wget -qi -
tar xjpvf utils.tar.bz2
rm utils.tar.bz2
. "$this_folder/bashutils.inc"
cd "$_pwd"
# --- END include bashutils SECTION ---
```

- add script function to update `bashutils.inc` whenever we need
```
update_bashutils(){
  echo "[update_bashutils] ..."

  _pwd=`pwd`
  cd "$this_folder"

  curl -s https://api.github.com/repos/tgedr/bashutils/releases/latest \
  | grep "browser_download_url.*utils\.tar\.bz2" \
  | cut -d '"' -f 4 | wget -qi -
  tar xjpvf utils.tar.bz2
  if [ ! "$?" -eq "0" ] ; then echo "[update_bashutils] could not untar it" && cd "$_pwd" && return 1; fi
  rm utils.tar.bz2

  cd "$_pwd"
  echo "[update_bashutils] ...done."
}
```
