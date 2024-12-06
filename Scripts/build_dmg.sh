#!/bin/bash

name="PlayEm"
app_name="${name}.app"

plist_buddy_bin="/usr/libexec/PlistBuddy"
plist_path="${app_name}/Contents/Info.plist")

version="v"$($plist_buddy_bin -c "Print :CFBundleShortVersionString" $plist_path)
version="${version}."$($plist_buddy_bin -c "Print :CFBundleVersion" $plist_path)

destination_path="${name}.${version}/"
dmg_name="${name}.${version}.dmg"

rm "${dmg_name}"
rm -rf "${destination_path}"

mkdir "${destination_path}"
cp -R "${app_name}" "${destination_path}"
cp LICENSE "${destination_path}"

create-dmg \
  --volname "${name}" \
  --window-pos 200 120 \
  --window-size 504 300 \
  --icon-size 100 \
  --text-size 15 \
  --hide-extension "${app_name}" \
  --app-drop-link 300 20 \
  --icon "${app_name}" 90 20 \
  --icon LICENSE 300 170 \
  "${dmg_name}" \
  "${destination_path}"

rm -rf "${destination_path}"
