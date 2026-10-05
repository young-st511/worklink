#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
destination="$HOME/Applications/Worklink.app"
if [ ! -d .build/Worklink.app ]; then
  printf '%s\n' '먼저 make app을 실행해 주세요.' >&2
  exit 1
fi
if [ -e "$destination" ]; then
  printf '%s\n' '이미 설치된 Worklink가 있습니다. 앱을 종료하고 기존 앱을 옮긴 뒤 다시 실행해 주세요.' >&2
  exit 1
fi
mkdir -p "$HOME/Applications"
ditto .build/Worklink.app "$destination"
printf '설치 완료: %s\n' "$destination"
printf '%s\n' 'Finder에서 앱을 열고 기존 SSH 별칭을 등록해 주세요.'
