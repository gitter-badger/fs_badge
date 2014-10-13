#!/bin/bash

tail -n +4 $1 | xxd -r -p | http POST https://agent.electricimp.com/sO_clT732DeD/WIFimage
