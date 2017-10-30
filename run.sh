#!/bin/bash

trap "exit 1" TERM
export TOP_PID=$$

function stderr(){
	# For user messages.
	echo -e $1 >&2
}

function username2id(){
	# Convert the username (offically they called nickname) to userid.
	# The format for userid is \d+
	id=`curl -s "https://www.plurk.com/$1" | grep -oh 'showFriends?user_id=.*&page=all' | sed -e 's/showFriends?user_id=//g' -e 's/&page=all//g'`
	[ -z "$id" ] && stderr 'User not exist, Exiting...' && kill -s TERM $TOP_PID
	echo $id
}

function getuserdata(){
	echo "-----------$2-----------"
	curl -s 'https://www.plurk.com/Users/getUserData' --data "page_uid=$1" | jq -r '"Fans: " + (.num_of_fans | tostring) + "\n" + "Friend: " + (.num_of_friends | tostring)'
	curl -s "https://www.plurk.com/$2" | grep -oP 'var GLOBAL = \K.*' | sed 's/"date_of_birth":new Date(".\{1,30\}"),//g' | jq -r '"Full name: " + .page_user.full_name + "\n" + "Display name: " + .page_user.display_name'
}

function get_friends_by_offset(){
	# Print the friend list (user ID) of a specific user ID to stdout.
	userid=$1
	stderr "- User id: $userid"
	friendcount=`get_friends_count $userid`
	offset=0
	while true
	do
		stderr "- Fetch $offset of $friendcount"
		res=`curl -s 'https://www.plurk.com/Friends/getFriendsByOffset' --data "offset=$offset&user_id=$userid"`
		[ "$res" == '[]' ] && return 0
		echo $res | sed 's/"date_of_birth":\ new Date(".\{1,30\}"),//g' | jq -r '.[] | if (.is_disabled == false) then [(.uid | tostring), .nick_name] | join(",") else empty end'
		offset=$(($offset + 10))
	done
}

function get_friends_count(){
	# Get friends count, but doesn't check the username, so be sure check the username existence before use.
	userid=$1
	echo `curl -s "https://www.plurk.com/Friends/showFriends?user_id=$userid&page=" | grep -oP "'friends',.+?,\s\K\d+"`
}

function and_list(){
	# List $1 and list $2 both have the plurk.
	# A跟B都有看到
	awk 'FNR==NR{ array[$0]; next} {if ( $1 in array ) print $1 ;next}' $1 $2
}

function subtract_list(){
	# List $1 have the item, but list $2 doesn't.
	# A有看到B沒看到
	awk 'FNR==NR{ array[$0]; next} {if ( $1 in array ) next; print $1}' $2 $1
}

function clean_up(){
	rm -f tmp
	rm -f tmp_final
}

clean_up
c=1
total=`wc -l rule`
while read line
do
	stderr "$c of $total:"
	rule=${line:0:1}
	username=${line:1:${#line}-1}
	stderr "Fetch friends list of $username" && get_friends_by_offset `username2id $username` > tmp
	[ $c -eq 1 ] && mv tmp tmp_final
	[ $c -gt 1 ] && [ "$rule" == "+" ] && echo "$username can see the plurk" && and_list tmp_final tmp > tmp_tmp
	[ $c -gt 1 ] && [ "$rule" == "-" ] && echo "$username cannot see the plurk" && subtract_list tmp_final tmp > tmp_tmp
	[ $c -gt 1 ] && rm tmp_final tmp && mv tmp_tmp tmp_final
	c=$(($c + 1))
done < rule

stderr "\n\nList possible person:\n"
while read line
do
	userid=`echo $line | awk -F ',' '{print $1}'`
	username=`echo $line | awk -F ',' '{print $2}'`
	getuserdata $userid $username
done < tmp_final

clean_up
