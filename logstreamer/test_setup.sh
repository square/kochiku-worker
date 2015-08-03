#!/bin/bash

mkdir -p logs/100/
mkdir -p logs/101/

cat > logs/100/stdout.log <<EOF
Hello
line 2
line 3
line 4
EOF

cat > logs/101/stdout.log <<EOF
This is a test log file.
This is line 2
This is line 3
EOF

