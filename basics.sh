#!/bin/bash
# Basic view from supportconfig

# functions
osver() {
	echo
}
sysver() {

	VER=$(sed -n '/^#.*uname -a$/,/^#=/{/^#=/q;p}' basic-environment.txt|grep -v ^#|awk '{print $3}')
	export VER
	echo -n "KERNEL: "
	sed -n '/^#.*uname -a$/,/^#=/{/^#=/q;p}' basic-environment.txt|grep -v ^#
	kernel_check.py $VER
}

tainted() {
	sed -n '/^#.*tainted$/,/^#=/{/^#=/q;p}' basic-health-check.txt
}
productf() {
	sed -n '/^#.*products.d\/$/,/^#=/{/^#=/q;p}' updates.txt |grep -vE '^(#|total|$)'|awk '{print $NF}'
}








##### MAIN program
#echo "-------------------------------------"
echo "--"
productf
echo
echo "--"
sysver
echo

echo "--"
tainted
echo
