#!/bin/bash

# example
# for module in $(ls /data/work/puppetrepo/trunk/modules); do /data/work/chkMod-withDiff.sh $module branches/lab/lab0; done | grep -v "Total diffs: 0"

compare=trunk
wdbase=/data/work/puppetrepo
SVN=/usr/bin/svn
mod=modules/$1
[ $2 ] && branch=$2
REPO="http://puppetrepo1.sea5.speakeasy.priv/puppet"
count1=0; FileCount=0; DifferCount=0; ident=0

#$SVN merge -r 3100:HEAD --dry-run $wdbase/$compare/$mod $wdbase/$branch/$mod | egrep -v "Merging" | while read MGR; do

# redirecting like that is Not POSIX complaint, but otherwise piping to while loop creates a sub shell and dificalties getting variables from it
while read DIFF; do
	((count1++))
	str="$(echo $REPO | sed 's/\//\\\//g')"
	fileCom=$(echo $DIFF | sed "s/$str\///g")
	[ -f $wdbase/$fileCom ] && {
		((FileCount++))
		b=$(echo $branch | sed 's/\//\\\//g')
		fileTo=$(echo $fileCom | sed "s/trunk/$b/g")
		reading=$(diff -s -q $wdbase/$fileCom $wdbase/$fileTo | sed 's/and//g')
		case "$(echo $reading | awk '{print $NF}')" in
			identical)	((ident++));;
			*)			((DifferCount++)); echo $reading;;
		esac
	}
done < <($SVN diff --summarize $REPO/$compare/$mod $REPO/$branch/$mod | awk '{print $NF}')

echo -e '\E[33m'"\033[1m$1\033[0m of $branch\t Total diffs: $count1\t Diff files: $FileCount\tIdentical: $ident\tReal diffs: $DifferCount"
