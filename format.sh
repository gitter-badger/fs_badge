#!/bin/bash

convert -resize 264x176 -colorspace Gray -gravity center -background white -extent 264x176 -rotate 180 "$1" "${1/png/xbm}"
convert "${1/png/xbm}" preview.png && open preview.png

