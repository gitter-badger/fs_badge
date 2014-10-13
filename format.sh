#!/bin/bash

convert -resize 264x176 -colorspace Gray -rotate 180 -negate $1 $1.xbm
