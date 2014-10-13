#!/bin/bash

convert -pointsize 36 -font Helvetica -weight bold -colorspace Gray -size 264x176 canvas:none -fill black -negate +antialias -gravity Center -type Bilevel -draw "text 0,0 '$1'" -rotate 180 text.xbm
